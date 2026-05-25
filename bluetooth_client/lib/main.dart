import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_helpers.dart';

void main() {
  runApp(const BluetoothClientApp());
}

class BluetoothClientApp extends StatelessWidget {
  const BluetoothClientApp({super.key, this.controller});

  final BlePageController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE 桥接调试',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006C67),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F7),
        useMaterial3: true,
      ),
      home: BleDebugPage(controller: controller ?? RealBlePageController()),
    );
  }
}

class BleDeviceView {
  const BleDeviceView({
    required this.id,
    required this.name,
    required this.rssi,
    required this.signal,
    required this.connectable,
    this.scanResult,
  });

  final String id;
  final String name;
  final int rssi;
  final String signal;
  final bool connectable;
  final ScanResult? scanResult;
}

class BleConnectionDetails {
  const BleConnectionDetails({
    this.mtu,
    this.serviceCount = 0,
    this.writableServiceUuid,
    this.writableCharacteristicUuid,
    this.writeMode,
    this.connectedAt,
    this.lastSentText,
    this.lastSentBytes,
    this.lastSentAt,
  });

  final int? mtu;
  final int serviceCount;
  final String? writableServiceUuid;
  final String? writableCharacteristicUuid;
  final String? writeMode;
  final DateTime? connectedAt;
  final String? lastSentText;
  final int? lastSentBytes;
  final DateTime? lastSentAt;
}

abstract class BlePageController extends ChangeNotifier {
  bool get isScanning;
  bool get isBusy;
  bool get showUnknown;
  bool get isConnected;
  String get statusText;
  String? get lastError;
  List<BleDeviceView> get devices;
  BleDeviceView? get selectedDevice;
  BleConnectionDetails get details;

  set showUnknown(bool value);

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> selectDevice(BleDeviceView device);
  Future<void> connectSelected();
  Future<void> disconnectSelected();
  Future<void> sendMessage(String text);
}

class RealBlePageController extends BlePageController {
  static const MethodChannel _platformChannel = MethodChannel(
    'ble_bridge/platform',
  );

  final Map<String, ScanResult> _resultsById = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _isScanning = false;
  bool _isBusy = false;
  bool _showUnknown = false;
  bool _isConnected = false;
  String _statusText = '就绪';
  String? _lastError;
  BleDeviceView? _selectedDevice;
  BleConnectionDetails _details = const BleConnectionDetails();
  WritableTarget? _writableTarget;
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _manualDisconnecting = false;

  RealBlePageController() {
    _subscriptions.add(
      FlutterBluePlus.isScanning.listen((value) {
        _isScanning = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(FlutterBluePlus.scanResults.listen(_handleScanResults));
  }

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isBusy => _isBusy;

  @override
  bool get showUnknown => _showUnknown;

  @override
  set showUnknown(bool value) {
    if (_showUnknown == value) {
      return;
    }
    _showUnknown = value;
    notifyListeners();
  }

  @override
  bool get isConnected => _isConnected;

  @override
  String get statusText => _statusText;

  @override
  String? get lastError => _lastError;

  @override
  List<BleDeviceView> get devices {
    final results =
        _resultsById.values
            .where(
              (result) =>
                  shouldShowScanResult(result, showUnknown: _showUnknown),
            )
            .toList()
          ..sort(compareScanResultsBySignal);

    return results.map(_viewFromResult).toList();
  }

  @override
  BleDeviceView? get selectedDevice => _selectedDevice;

  @override
  BleConnectionDetails get details => _details;

  @override
  Future<void> startScan() async {
    await _runBusy(() async {
      _lastError = null;
      _statusText = '检查权限';
      notifyListeners();

      final permissionError = await _requestPermissions();
      if (permissionError != null) {
        _lastError = permissionError;
        _statusText = '需要权限';
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _lastError = '蓝牙当前为 ${adapterState.name}，请打开蓝牙后重试。';
        _statusText = '蓝牙未打开';
        return;
      }

      _resultsById.clear();
      _statusText = '扫描 10 秒';
      notifyListeners();

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: false,
        androidCheckLocationServices: false,
      );
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _statusText = devices.isEmpty ? '未发现设备' : '已停止扫描';
    notifyListeners();
  }

  @override
  Future<void> selectDevice(BleDeviceView device) async {
    _selectedDevice = device;
    _lastError = null;
    _statusText = '已选择 ${device.name}';
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    final selected = _selectedDevice;
    final result = selected?.scanResult;
    if (selected == null || result == null) {
      _lastError = '请先选择一台 BLE 设备。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        await FlutterBluePlus.stopScan();
        _statusText = '正在连接';
        _lastError = null;
        notifyListeners();

        final device = result.device;
        _connectedDevice = device;
        await _connectionSubscription?.cancel();
        await device.connect(
          license: License.free,
          timeout: const Duration(seconds: 15),
          mtu: 512,
        );

        _isConnected = true;
        _watchConnectionState(device);
        _statusText = '发现服务';
        notifyListeners();

        final services = await device.discoverServices(timeout: 15);
        final target = findWritableTarget(services);
        _writableTarget = target;
        _details = BleConnectionDetails(
          mtu: device.mtuNow,
          serviceCount: services.length,
          writableServiceUuid: target?.serviceUuid,
          writableCharacteristicUuid: target?.characteristicUuid,
          writeMode: target == null
              ? null
              : target.withoutResponse
              ? '无响应写'
              : '有响应写',
          connectedAt: DateTime.now(),
        );
        _statusText = target == null ? '已连接，但没有可写通道' : '已连接';
      } catch (error) {
        _isConnected = false;
        _writableTarget = null;
        _lastError = _friendlyError(error);
        _statusText = '连接失败';
      }
    });
  }

  @override
  Future<void> disconnectSelected() async {
    final device = _connectedDevice;
    await _runBusy(() async {
      _manualDisconnecting = true;
      try {
        if (device != null) {
          await device.disconnect(timeout: 10);
        }
        _isConnected = false;
        _writableTarget = null;
        _statusText = '已断开';
      } catch (error) {
        _lastError = _friendlyError(error);
        _statusText = '断开失败';
      } finally {
        _manualDisconnecting = false;
      }
    });
  }

  @override
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _lastError = '请先输入要发送的消息。';
      notifyListeners();
      return;
    }
    final target = _writableTarget;
    if (!_isConnected || target == null) {
      _lastError = '请先连接带可写 Characteristic 的设备。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        final bytes = utf8.encode(trimmed);
        await target.characteristic.write(
          bytes,
          withoutResponse: target.withoutResponse,
          timeout: 15,
        );
        _details = BleConnectionDetails(
          mtu: _details.mtu,
          serviceCount: _details.serviceCount,
          writableServiceUuid: _details.writableServiceUuid,
          writableCharacteristicUuid: _details.writableCharacteristicUuid,
          writeMode: _details.writeMode,
          connectedAt: _details.connectedAt,
          lastSentText: trimmed,
          lastSentBytes: bytes.length,
          lastSentAt: DateTime.now(),
        );
        _lastError = null;
        _statusText = '已发送';
      } catch (error) {
        _lastError = _friendlyError(error);
        _statusText = '发送失败';
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    _isBusy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<String?> _requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    final sdkInt = await _androidSdkInt();
    final permissions = blePermissionsForAndroidSdk(sdkInt);
    final statuses = await permissions.request();
    final denied = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();
    if (denied.isEmpty) {
      return null;
    }

    return '缺少权限: ${denied.map((permission) => permission.toString()).join(', ')}';
  }

  Future<int> _androidSdkInt() async {
    final sdkInt = await _platformChannel.invokeMethod<int>('androidSdkInt');
    return sdkInt ?? 31;
  }

  void _watchConnectionState(BluetoothDevice device) {
    _connectionSubscription = device.connectionState.listen((state) {
      if (state != BluetoothConnectionState.disconnected || !_isConnected) {
        return;
      }

      _isConnected = false;
      _writableTarget = null;
      if (!_manualDisconnecting) {
        _statusText = '设备已主动断开';
        _lastError = '设备已断开连接。';
      }
      notifyListeners();
    });
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      _resultsById[result.device.remoteId.str] = result;
    }

    if (_isScanning) {
      _statusText = _resultsById.isEmpty ? '扫描中' : '发现 ${devices.length} 台设备';
    }
    notifyListeners();
  }

  BleDeviceView _viewFromResult(ScanResult result) {
    return BleDeviceView(
      id: result.device.remoteId.str,
      name: displayDeviceName(result),
      rssi: result.rssi,
      signal: signalLabel(result.rssi),
      connectable: result.advertisementData.connectable,
      scanResult: result,
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Timed out')) {
      return '操作超时。';
    }
    if (text.contains('permission')) {
      return '需要蓝牙权限。';
    }
    if (text.contains('device is not connected')) {
      _isConnected = false;
      return '设备已断开连接。';
    }
    return text;
  }
}

class BleDebugPage extends StatefulWidget {
  const BleDebugPage({super.key, required this.controller});

  final BlePageController controller;

  @override
  State<BleDebugPage> createState() => _BleDebugPageState();
}

class _BleDebugPageState extends State<BleDebugPage> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE 桥接调试'),
            actions: [
              IconButton(
                tooltip: '重新扫描',
                onPressed: controller.isBusy ? null : controller.startScan,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(controller: controller),
                Expanded(child: _DeviceList(controller: controller)),
                _SendPanel(
                  controller: controller,
                  messageController: _messageController,
                ),
                _DetailsPanel(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final BlePageController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: controller.isBusy
                ? null
                : controller.isScanning
                ? controller.stopScan
                : controller.startScan,
            icon: Icon(controller.isScanning ? Icons.stop : Icons.radar),
            label: Text(controller.isScanning ? '停止' : '扫描'),
          ),
          const SizedBox(width: 10),
          FilterChip(
            selected: controller.showUnknown,
            onSelected: (value) => controller.showUnknown = value,
            label: const Text('显示未知'),
            avatar: const Icon(Icons.visibility, size: 18),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              controller.statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.controller});

  final BlePageController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            controller.isScanning ? '正在扫描附近 BLE 设备' : '还没有 BLE 设备',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemBuilder: (context, index) {
        final device = devices[index];
        final selected = controller.selectedDevice?.id == device.id;
        return _DeviceTile(
          device: device,
          selected: selected,
          onTap: () => controller.selectDevice(device),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: devices.length,
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final BleDeviceView device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary
                      : const Color(0xFFE7EFEF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.bluetooth,
                  color: selected ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${device.rssi} dBm',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    device.signal,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    device.connectable ? '可连接' : '广播',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendPanel extends StatelessWidget {
  const _SendPanel({required this.controller, required this.messageController});

  final BlePageController controller;
  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6E6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: messageController,
              minLines: 1,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: controller.isConnected
                  ? controller.sendMessage
                  : null,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.edit_note),
                hintText: selected == null ? '先选择设备' : '输入要写入设备的消息',
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: controller.isConnected ? '发送' : '请先连接',
            onPressed: controller.isConnected && !controller.isBusy
                ? () => controller.sendMessage(messageController.text)
                : null,
            icon: const Icon(Icons.send),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: selected == null || controller.isBusy
                ? null
                : controller.isConnected
                ? controller.disconnectSelected
                : controller.connectSelected,
            icon: Icon(controller.isConnected ? Icons.link_off : Icons.link),
            label: Text(controller.isConnected ? '断开蓝牙' : '连接蓝牙'),
          ),
        ],
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.controller});

  final BlePageController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    final details = controller.details;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(color: Color(0xFF112624)),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  '详情',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
                const Spacer(),
                Text(controller.isConnected ? '已连接' : '已断开'),
              ],
            ),
            const SizedBox(height: 8),
            _DetailLine(
              label: '选中设备',
              value: selected == null
                  ? '无'
                  : '${selected.name} (${selected.rssi} dBm)',
            ),
            _DetailLine(label: '设备 ID', value: selected?.id ?? '-'),
            _DetailLine(label: 'MTU', value: details.mtu?.toString() ?? '-'),
            _DetailLine(label: '服务数量', value: details.serviceCount.toString()),
            _DetailLine(label: '可写通道', value: _writableText(details)),
            _DetailLine(label: '最近发送', value: _lastSentText(details)),
            if (controller.lastError != null)
              _DetailLine(label: '错误', value: controller.lastError!),
          ],
        ),
      ),
    );
  }

  String _writableText(BleConnectionDetails details) {
    if (details.writableCharacteristicUuid == null) {
      return '-';
    }
    return '${details.writableServiceUuid} / ${details.writableCharacteristicUuid} (${details.writeMode})';
  }

  String _lastSentText(BleConnectionDetails details) {
    if (details.lastSentText == null) {
      return '-';
    }
    final bytes = details.lastSentBytes ?? 0;
    final time = details.lastSentAt == null
        ? ''
        : ' at ${_formatTime(details.lastSentAt!)}';
    return '"${details.lastSentText}" ($bytes bytes)$time';
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
