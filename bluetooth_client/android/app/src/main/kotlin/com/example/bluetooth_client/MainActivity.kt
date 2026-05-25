package com.example.bluetooth_client

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private var socket: BluetoothSocket? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermission: PendingPermission? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listBondedDevices" -> listBondedDevices(result)
                    "connect" -> {
                        val address = call.argument<String>("address")
                        val uuid = call.argument<String>("uuid") ?: SPP_UUID
                        val channel = call.argument<Int>("channel") ?: DEFAULT_RFCOMM_CHANNEL
                        connect(address, uuid, channel, result)
                    }
                    "disconnect" -> disconnect(result)
                    "send" -> {
                        val text = call.argument<String>("text")
                        send(text, result)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                },
            )
    }

    override fun onDestroy() {
        closeSocket()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLUETOOTH_CONNECT) {
            return
        }

        val request = pendingPermission ?: return
        pendingPermission = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            request.onGranted()
        } else {
            request.onDenied()
        }
    }

    private fun listBondedDevices(result: MethodChannel.Result) {
        withBluetoothConnectPermission(result) {
            listBondedDevicesWithPermission(result)
        }
    }

    private fun listBondedDevicesWithPermission(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("no_adapter", "Bluetooth adapter is not available.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_off", "Bluetooth is turned off.", null)
            return
        }

        val devices = adapter.bondedDevices
            .map { device ->
                mapOf(
                    "name" to device.safeName(),
                    "address" to device.address,
                )
            }
            .sortedWith(
                compareBy<Map<String, String>> { it["name"].orEmpty().lowercase() }
                    .thenBy { it["address"].orEmpty() },
            )
        result.success(devices)
    }

    private fun connect(
        address: String?,
        uuidText: String,
        channel: Int,
        result: MethodChannel.Result,
    ) {
        if (address.isNullOrBlank()) {
            result.error("missing_address", "Device address is required.", null)
            return
        }
        withBluetoothConnectPermission(result) {
            connectWithPermission(address, uuidText, channel, result)
        }
    }

    private fun connectWithPermission(
        address: String,
        uuidText: String,
        channel: Int,
        result: MethodChannel.Result,
    ) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("no_adapter", "Bluetooth adapter is not available.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_off", "Bluetooth is turned off.", null)
            return
        }

        val uuid = try {
            UUID.fromString(uuidText)
        } catch (error: IllegalArgumentException) {
            result.error("bad_uuid", "Invalid RFCOMM UUID.", null)
            return
        }

        executor.execute {
            try {
                closeSocket()
                val device = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()
                val nextSocket = connectWithFallback(device, uuid, channel)
                socket = nextSocket
                runOnUiThread {
                    result.success(null)
                    publish(mapOf("type" to "connected", "address" to address))
                }
                readLoop(nextSocket)
            } catch (error: Exception) {
                closeSocket()
                runOnUiThread {
                    result.error("connect_failed", error.message ?: "RFCOMM connect failed.", null)
                    publish(mapOf("type" to "error", "message" to (error.message ?: "connect failed")))
                }
            }
        }
    }

    private fun connectWithFallback(
        device: BluetoothDevice,
        uuid: UUID,
        channel: Int,
    ): BluetoothSocket {
        val primary = device.createRfcommSocketToServiceRecord(uuid)
        try {
            primary.connect()
            return primary
        } catch (error: Exception) {
            try {
                primary.close()
            } catch (_: Exception) {
            }
            val fallback = createRfcommSocketByChannel(device, channel)
            fallback.connect()
            return fallback
        }
    }

    private fun createRfcommSocketByChannel(
        device: BluetoothDevice,
        channel: Int,
    ): BluetoothSocket {
        val method = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
        return method.invoke(device, channel) as BluetoothSocket
    }

    private fun send(text: String?, result: MethodChannel.Result) {
        val currentSocket = socket
        if (currentSocket == null || !currentSocket.isConnected) {
            result.error("not_connected", "RFCOMM socket is not connected.", null)
            return
        }
        val payload = text?.trim()
        if (payload.isNullOrEmpty()) {
            result.error("empty_message", "Message is empty.", null)
            return
        }

        executor.execute {
            try {
                currentSocket.outputStream.write((payload + "\n").toByteArray(Charsets.UTF_8))
                currentSocket.outputStream.flush()
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("send_failed", error.message ?: "RFCOMM send failed.", null)
                    publish(mapOf("type" to "error", "message" to (error.message ?: "send failed")))
                }
            }
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        executor.execute {
            closeSocket()
            runOnUiThread {
                result.success(null)
                publish(mapOf("type" to "disconnected"))
            }
        }
    }

    private fun readLoop(currentSocket: BluetoothSocket) {
        try {
            val reader = BufferedReader(InputStreamReader(currentSocket.inputStream, Charsets.UTF_8))
            while (currentSocket.isConnected) {
                val line = reader.readLine() ?: break
                runOnUiThread { publish(mapOf("type" to "received", "text" to line)) }
            }
        } catch (error: Exception) {
            runOnUiThread {
                publish(mapOf("type" to "error", "message" to (error.message ?: "read failed")))
            }
        } finally {
            closeSocket()
            runOnUiThread { publish(mapOf("type" to "disconnected")) }
        }
    }

    private fun closeSocket() {
        try {
            socket?.close()
        } catch (_: Exception) {
        } finally {
            socket = null
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(BluetoothManager::class.java)
        return manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }

    private fun withBluetoothConnectPermission(
        result: MethodChannel.Result,
        action: () -> Unit,
    ) {
        if (hasBluetoothConnectPermission()) {
            action()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.error("missing_permission", "Bluetooth connect permission is required.", null)
            return
        }
        if (pendingPermission != null) {
            result.error("permission_pending", "Bluetooth permission request is already open.", null)
            return
        }

        pendingPermission = PendingPermission(
            onGranted = action,
            onDenied = {
                result.error(
                    "missing_permission",
                    "Bluetooth connect permission is required.",
                    null,
                )
            },
        )
        requestPermissions(
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            REQUEST_BLUETOOTH_CONNECT,
        )
    }

    private fun BluetoothDevice.safeName(): String {
        return try {
            name ?: ""
        } catch (_: SecurityException) {
            ""
        }
    }

    private fun publish(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    companion object {
        private const val CONTROL_CHANNEL = "rfcomm_bridge/control"
        private const val EVENTS_CHANNEL = "rfcomm_bridge/events"
        private const val SPP_UUID = "00001101-0000-1000-8000-00805F9B34FB"
        private const val DEFAULT_RFCOMM_CHANNEL = 4
        private const val REQUEST_BLUETOOTH_CONNECT = 42
    }

    private data class PendingPermission(
        val onGranted: () -> Unit,
        val onDenied: () -> Unit,
    )
}
