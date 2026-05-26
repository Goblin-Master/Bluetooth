import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_helpers.dart';
import 'rfcomm_helpers.dart';

void main() {
  runApp(const BluetoothClientApp());
}

class BluetoothClientApp extends StatelessWidget {
  const BluetoothClientApp({super.key, this.controller, this.bleController});

  final RfcommController? controller;
  final BleController? bleController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth 调试',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006C67),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F7),
        useMaterial3: true,
      ),
      home: BluetoothClientHome(
        rfcommController: controller ?? RealRfcommController(),
        bleController: bleController ?? RealBleController(),
      ),
    );
  }
}

class BluetoothClientHome extends StatelessWidget {
  const BluetoothClientHome({
    super.key,
    required this.rfcommController,
    required this.bleController,
  });

  final RfcommController rfcommController;
  final BleController bleController;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bluetooth 调试'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'RFCOMM', icon: Icon(Icons.bluetooth_connected)),
              Tab(text: 'BLE', icon: Icon(Icons.bluetooth_searching)),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              RfcommDebugPage(controller: rfcommController),
              BleGattDebugPage(controller: bleController),
            ],
          ),
        ),
      ),
    );
  }
}

abstract class RfcommController extends ChangeNotifier {
  bool get isBusy;
  bool get isConnected;
  String get statusText;
  String? get lastError;
  String? get lastReceivedText;
  OutboundMessage? get lastSentMessage;
  List<PairedBluetoothDevice> get devices;
  PairedBluetoothDevice? get selectedDevice;
  int get rfcommChannel;

  void setRfcommChannelFromInput(String input);
  Future<void> refreshPairedDevices();
  Future<void> selectDevice(PairedBluetoothDevice device);
  Future<void> connectSelected();
  Future<void> disconnect();
  Future<void> sendMessage(String text);
}

abstract class BleController extends ChangeNotifier {
  bool get isBusy;
  bool get isScanning;
  bool get isConnected;
  bool get showAllNamedDevices;
  BleMode get mode;
  String get statusText;
  String? get lastError;
  String? get lastReceivedText;
  OutboundMessage? get lastSentMessage;
  List<BleDeviceInfo> get devices;
  BleDeviceInfo? get selectedDevice;
  List<BleCharacteristicInfo> get explorerCharacteristics;
  BleCharacteristicInfo? get selectedCharacteristic;
  int? get mtu;
  int get serviceCount;
  String? get connectedAtText;
  String? get characteristicPropertiesText;

  void setMode(BleMode value);
  void setShowAllNamedDevices(bool value);
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> selectDevice(BleDeviceInfo device);
  Future<void> selectCharacteristic(BleCharacteristicInfo characteristic);
  Future<void> connectSelected();
  Future<void> disconnect();
  Future<void> sendMessage(String text);
}

class RealBleController extends BleController {
  final Map<String, _ScannedBleDevice> _scanResults = {};
  final Map<String, BluetoothCharacteristic> _characteristicResults = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _selectedBleCharacteristic;
  BleDeviceInfo? _selectedDevice;
  BleCharacteristicInfo? _selectedCharacteristic;
  List<BleCharacteristicInfo> _explorerCharacteristics = [];
  OutboundMessage? _lastSentMessage;
  bool _isBusy = false;
  bool _isScanning = false;
  bool _isConnected = false;
  bool _showAllNamedDevices = false;
  BleMode _mode = BleMode.bridge;
  int? _mtu;
  int _serviceCount = 0;
  String _statusText = '就绪';
  String? _lastError;
  String? _lastReceivedText;
  String? _connectedAtText;
  String? _characteristicPropertiesText;

  RealBleController() {
    _subscriptions.add(
      FlutterBluePlus.scanResults.listen(
        _handleScanResults,
        onError: (Object error) => _setError('扫描失败', error),
      ),
    );
    _subscriptions.add(
      FlutterBluePlus.isScanning.listen((value) {
        _isScanning = value;
        notifyListeners();
      }),
    );
  }

  @override
  bool get isBusy => _isBusy;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isConnected => _isConnected;

  @override
  bool get showAllNamedDevices => _showAllNamedDevices;

  @override
  BleMode get mode => _mode;

  @override
  String get statusText => _statusText;

  @override
  String? get lastError => _lastError;

  @override
  String? get lastReceivedText => _lastReceivedText;

  @override
  OutboundMessage? get lastSentMessage => _lastSentMessage;

  List<BleDeviceInfo> get _visibleBridgeDevices => filterBleDevices(
    _scanResults.values.map((entry) => entry.info),
    showAllNamedDevices: _showAllNamedDevices,
  );

  List<BleDeviceInfo> get _visibleExplorerDevices => filterExplorerDevices(
    _scanResults.values.map((entry) => entry.info),
    showUnnamedDevices: _showAllNamedDevices,
  );

  @override
  List<BleDeviceInfo> get devices =>
      _mode == BleMode.bridge ? _visibleBridgeDevices : _visibleExplorerDevices;

  @override
  BleDeviceInfo? get selectedDevice => _selectedDevice;

  @override
  List<BleCharacteristicInfo> get explorerCharacteristics =>
      List.unmodifiable(_explorerCharacteristics);

  @override
  BleCharacteristicInfo? get selectedCharacteristic => _selectedCharacteristic;

  @override
  int? get mtu => _mtu;

  @override
  int get serviceCount => _serviceCount;

  @override
  String? get connectedAtText => _connectedAtText;

  @override
  String? get characteristicPropertiesText => _characteristicPropertiesText;

  @override
  void setMode(BleMode value) {
    if (_mode == value) {
      return;
    }
    _mode = value;
    _selectedDevice = null;
    _selectedBleCharacteristic = null;
    _selectedCharacteristic = null;
    _explorerCharacteristics = [];
    _characteristicResults.clear();
    _lastError = null;
    _lastReceivedText = null;
    _characteristicPropertiesText = null;
    _statusText = value == BleMode.bridge ? 'Bridge 模式' : 'Explorer 模式';
    notifyListeners();
  }

  @override
  void setShowAllNamedDevices(bool value) {
    _showAllNamedDevices = value;
    notifyListeners();
  }

  @override
  Future<void> startScan() async {
    await _runBusy(() async {
      try {
        _lastError = null;
        _lastReceivedText = null;
        _characteristicPropertiesText = null;
        _explorerCharacteristics = [];
        _selectedCharacteristic = null;
        _selectedBleCharacteristic = null;
        _characteristicResults.clear();
        await _ensureBleReady();
        _scanResults.clear();
        _selectedDevice = null;
        _statusText = '扫描中';
        await FlutterBluePlus.startScan(
          withServices: defaultBleScanServiceFilters.map(Guid.new).toList(),
          timeout: const Duration(seconds: 10),
          continuousUpdates: true,
          androidUsesFineLocation: false,
          androidCheckLocationServices: false,
        );
      } catch (error) {
        _setError('扫描失败', error);
      }
    });
  }

  @override
  Future<void> stopScan() async {
    await _runBusy(() async {
      try {
        await FlutterBluePlus.stopScan();
        _isScanning = false;
        _statusText = _scanResults.isEmpty ? '没有扫描到设备' : '已停止扫描';
      } catch (error) {
        _setError('停止扫描失败', error);
      }
    });
  }

  @override
  Future<void> selectDevice(BleDeviceInfo device) async {
    _selectedDevice = device;
    _lastError = null;
    _lastReceivedText = null;
    _selectedBleCharacteristic = null;
    _selectedCharacteristic = null;
    _explorerCharacteristics = [];
    _characteristicResults.clear();
    _statusText = '已选择 ${device.name}';
    notifyListeners();
  }

  @override
  Future<void> selectCharacteristic(
    BleCharacteristicInfo characteristic,
  ) async {
    _selectedCharacteristic = characteristic;
    _selectedBleCharacteristic = _characteristicResults[characteristic.id];
    _characteristicPropertiesText = characteristic.propertiesText;
    _lastError = null;
    _statusText = '已选择 Characteristic';
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    final selected = _selectedDevice;
    if (selected == null) {
      _lastError = '请先选择 BLE 设备。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        await FlutterBluePlus.stopScan();
        _isScanning = false;
        _lastError = null;
        _lastReceivedText = null;
        _statusText = '正在连接 ${selected.name}';

        final device = _scanResults[selected.id]?.device;
        if (device == null) {
          throw StateError('设备不在当前扫描结果里，请重新扫描。');
        }

        await device.connect(
          license: License.free,
          timeout: const Duration(seconds: 15),
          mtu: 512,
        );
        _connectedDevice = device;
        _isConnected = true;
        _mtu = device.mtuNow;

        await _clearGattCacheIfPossible(device);
        final services = await device.discoverServices(timeout: 15);
        _serviceCount = services.length;
        if (_mode == BleMode.bridge) {
          _selectedBleCharacteristic = _findBridgeCharacteristic(services);
          if (_selectedBleCharacteristic == null) {
            throw StateError('未发现固定 BLE GATT Characteristic。');
          }
          _selectedCharacteristic = _infoForCharacteristic(
            _selectedBleCharacteristic!,
          );
        } else {
          _indexExplorerCharacteristics(services);
          _selectedCharacteristic = _firstWritableCharacteristic();
          if (_selectedCharacteristic == null) {
            throw StateError('没有发现可写 Characteristic。');
          }
          _selectedBleCharacteristic =
              _characteristicResults[_selectedCharacteristic!.id];
        }
        _characteristicPropertiesText = _describeCharacteristicProperties(
          _selectedBleCharacteristic!,
        );

        final notifyCharacteristic = _selectedBleCharacteristic!;
        _subscriptions.add(
          notifyCharacteristic.onValueReceived.listen(_handleNotification),
        );
        if (notifyCharacteristic.properties.notify ||
            notifyCharacteristic.properties.indicate) {
          await notifyCharacteristic.setNotifyValue(true);
        }

        _connectedAtText = _formatClockTime(DateTime.now());
        _statusText = '已连接 ${selected.name}';
      } catch (error) {
        _isConnected = false;
        _selectedBleCharacteristic = null;
        _setError('连接失败', error);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _runBusy(() async {
      try {
        await _connectedDevice?.disconnect();
        _isConnected = false;
        _selectedBleCharacteristic = null;
        _statusText = '已断开';
      } catch (error) {
        _setError('断开失败', error);
      }
    });
  }

  @override
  Future<void> sendMessage(String text) async {
    if (!_isConnected || _selectedBleCharacteristic == null) {
      _lastError = '请先连接 BLE GATT 服务。';
      notifyListeners();
      return;
    }

    late final OutboundMessage message;
    try {
      message = OutboundMessage.fromInput(text);
    } on ArgumentError {
      _lastError = '请先输入要发送的消息。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        final characteristic = _selectedBleCharacteristic!;
        final writeMode = _writeModeFor(characteristic);
        if (writeMode == BleWriteMode.unsupported) {
          throw StateError(
            '当前 Characteristic 不支持写入。实际属性：'
            '${_describeCharacteristicProperties(characteristic)}',
          );
        }
        await characteristic.write(
          utf8.encode(message.text),
          withoutResponse: writeMode == BleWriteMode.withoutResponse,
        );
        _lastSentMessage = message;
        _lastError = null;
        _statusText = '已发送';
      } catch (error) {
        _setError('发送失败', error);
      }
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _ensureBleReady() async {
    if (kIsWeb || !Platform.isAndroid) {
      throw StateError('BLE 调试只支持 Android 真机。');
    }

    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final denied = permissions.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .join(', ');
    if (denied.isNotEmpty) {
      throw StateError('缺少 BLE 权限：$denied');
    }

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw StateError('当前手机不支持 BLE。');
    }
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError('请先打开手机蓝牙。');
    }
  }

  BluetoothCharacteristic? _findBridgeCharacteristic(
    List<BluetoothService> services,
  ) {
    final serviceId = Guid(bleBridgeServiceUuid);
    final characteristicId = Guid(bleBridgeCharacteristicUuid);
    for (final service in services) {
      if (service.uuid != serviceId) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == characteristicId) {
          return characteristic;
        }
      }
    }
    return null;
  }

  void _indexExplorerCharacteristics(List<BluetoothService> services) {
    _characteristicResults.clear();
    _explorerCharacteristics = [];
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final info = _infoForCharacteristic(characteristic);
        _characteristicResults[info.id] = characteristic;
        _explorerCharacteristics.add(info);
      }
    }
    _explorerCharacteristics.sort((a, b) {
      if (a.isWritable != b.isWritable) {
        return a.isWritable ? -1 : 1;
      }
      final byService = a.serviceUuid.compareTo(b.serviceUuid);
      if (byService != 0) {
        return byService;
      }
      return a.characteristicUuid.compareTo(b.characteristicUuid);
    });
  }

  BleCharacteristicInfo? _firstWritableCharacteristic() {
    for (final characteristic in _explorerCharacteristics) {
      if (characteristic.isWritable) {
        return characteristic;
      }
    }
    return null;
  }

  BleCharacteristicInfo _infoForCharacteristic(
    BluetoothCharacteristic characteristic,
  ) {
    final properties = characteristic.properties;
    final id = [
      characteristic.serviceUuid.toString(),
      characteristic.characteristicUuid.toString(),
      characteristic.instanceId.toString(),
    ].join('|');
    return BleCharacteristicInfo(
      id: id,
      serviceUuid: characteristic.serviceUuid.toString(),
      characteristicUuid: characteristic.characteristicUuid.toString(),
      propertiesText: _describeCharacteristicProperties(characteristic),
      canWrite: properties.write,
      canWriteWithoutResponse: properties.writeWithoutResponse,
    );
  }

  Future<void> _clearGattCacheIfPossible(BluetoothDevice device) async {
    try {
      await device.clearGattCache();
    } catch (_) {
      // Cache clearing is best-effort. Discovery below still reports the
      // actual properties Android is currently using.
    }
  }

  BleWriteMode _writeModeFor(BluetoothCharacteristic characteristic) {
    final properties = characteristic.properties;
    return selectBleWriteMode(
      canWrite: properties.write,
      canWriteWithoutResponse: properties.writeWithoutResponse,
    );
  }

  String _describeCharacteristicProperties(
    BluetoothCharacteristic characteristic,
  ) {
    final properties = characteristic.properties;
    final labels = [
      if (properties.read) 'read',
      if (properties.write) 'write',
      if (properties.writeWithoutResponse) 'writeWithoutResponse',
      if (properties.notify) 'notify',
      if (properties.indicate) 'indicate',
      if (properties.broadcast) 'broadcast',
      if (properties.authenticatedSignedWrites) 'authenticatedSignedWrites',
      if (properties.extendedProperties) 'extendedProperties',
      if (properties.notifyEncryptionRequired) 'notifyEncryptionRequired',
      if (properties.indicateEncryptionRequired) 'indicateEncryptionRequired',
    ];
    return labels.isEmpty ? 'none' : labels.join(', ');
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final id = result.device.remoteId.toString();
      final name = _bestBleName(result);
      final advertisesBridgeService = result.advertisementData.serviceUuids
          .contains(Guid(bleBridgeServiceUuid));
      _scanResults[id] = _ScannedBleDevice(
        device: result.device,
        info: BleDeviceInfo(
          id: id,
          name: name,
          rssi: result.rssi,
          advertisesBridgeService: advertisesBridgeService,
        ),
      );
    }
    if (_isScanning) {
      _statusText = _scanResults.isEmpty
          ? '扫描中'
          : '扫描到 ${devices.length} 台可显示设备';
    }
    notifyListeners();
  }

  String _bestBleName(ScanResult result) {
    final names = [
      result.device.platformName,
      result.advertisementData.advName,
      result.device.advName,
    ];
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'Unknown';
  }

  void _handleNotification(List<int> value) {
    _lastReceivedText = utf8.decode(value, allowMalformed: true).trim();
    _statusText = '收到回包';
    notifyListeners();
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

  void _setError(String status, Object error) {
    _lastError = _friendlyBleError(error);
    _statusText = status;
    notifyListeners();
  }

  String _friendlyBleError(Object error) {
    final text = error.toString();
    if (text.contains('bluetoothScan') || text.contains('BLUETOOTH_SCAN')) {
      return '需要附近设备权限。';
    }
    if (text.contains('bluetoothConnect') ||
        text.contains('BLUETOOTH_CONNECT')) {
      return '需要蓝牙连接权限。';
    }
    return text;
  }

  String _formatClockTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _ScannedBleDevice {
  const _ScannedBleDevice({required this.device, required this.info});

  final BluetoothDevice device;
  final BleDeviceInfo info;
}

class RealRfcommController extends RfcommController {
  static const MethodChannel _channel = MethodChannel('rfcomm_bridge/control');
  static const EventChannel _events = EventChannel('rfcomm_bridge/events');

  final StreamSubscription<dynamic> _eventSubscription;
  List<PairedBluetoothDevice> _devices = [];
  PairedBluetoothDevice? _selectedDevice;
  OutboundMessage? _lastSentMessage;
  bool _isBusy = false;
  bool _isConnected = false;
  int _rfcommChannel = defaultRfcommChannel;
  String _statusText = '就绪';
  String? _lastError;
  String? _lastReceivedText;

  RealRfcommController()
    : _eventSubscription = _events.receiveBroadcastStream().listen(null) {
    _eventSubscription.onData(_handleNativeEvent);
    unawaited(refreshPairedDevices());
  }

  @override
  bool get isBusy => _isBusy;

  @override
  bool get isConnected => _isConnected;

  @override
  String get statusText => _statusText;

  @override
  String? get lastError => _lastError;

  @override
  String? get lastReceivedText => _lastReceivedText;

  @override
  OutboundMessage? get lastSentMessage => _lastSentMessage;

  @override
  List<PairedBluetoothDevice> get devices => List.unmodifiable(_devices);

  @override
  PairedBluetoothDevice? get selectedDevice => _selectedDevice;

  @override
  int get rfcommChannel => _rfcommChannel;

  @override
  void setRfcommChannelFromInput(String input) {
    try {
      _rfcommChannel = normalizeRfcommChannel(input);
      _lastError = null;
    } on ArgumentError {
      _lastError = 'RFCOMM channel 必须是 1-30。';
    }
    notifyListeners();
  }

  @override
  Future<void> refreshPairedDevices() async {
    await _runBusy(() async {
      try {
        _lastError = null;
        if (kIsWeb || !Platform.isAndroid) {
          _statusText = '仅支持 Android 真机';
          _devices = [];
          return;
        }

        _statusText = '加载已配对设备';
        final rawDevices = await _channel.invokeMethod<List<dynamic>>(
          'listBondedDevices',
        );
        _devices =
            (rawDevices ?? [])
                .whereType<Map<dynamic, dynamic>>()
                .map(PairedBluetoothDevice.fromMap)
                .where((device) => device.address.isNotEmpty)
                .toList()
              ..sort(comparePairedDevices);

        if (_selectedDevice != null &&
            !_devices.any(
              (device) => device.address == _selectedDevice!.address,
            )) {
          _selectedDevice = null;
          _isConnected = false;
        }

        _statusText = _devices.isEmpty ? '没有已配对设备' : '已加载 ${_devices.length} 台';
      } catch (error) {
        _lastError = _friendlyError(error);
        _statusText = '加载失败';
      }
    });
  }

  @override
  Future<void> selectDevice(PairedBluetoothDevice device) async {
    _selectedDevice = device;
    _lastError = null;
    _lastReceivedText = null;
    _statusText = '已选择 ${device.label}';
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    final selected = _selectedDevice;
    if (selected == null) {
      _lastError = '请先选择 Windows 电脑。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        _lastError = null;
        _lastReceivedText = null;
        _statusText = '正在连接 ${selected.label}';
        await _channel.invokeMethod<void>('connect', {
          'address': selected.address,
          'uuid': defaultSppUuid,
          'channel': _rfcommChannel,
        });
        _isConnected = true;
        _statusText = '已连接 ${selected.label}';
      } catch (error) {
        _isConnected = false;
        _lastError = _friendlyError(error);
        _statusText = '连接失败';
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _runBusy(() async {
      try {
        await _channel.invokeMethod<void>('disconnect');
        _isConnected = false;
        _statusText = '已断开';
      } catch (error) {
        _lastError = _friendlyError(error);
        _statusText = '断开失败';
      }
    });
  }

  @override
  Future<void> sendMessage(String text) async {
    if (!_isConnected) {
      _lastError = '请先连接 Windows RFCOMM 服务。';
      notifyListeners();
      return;
    }

    late final OutboundMessage message;
    try {
      message = OutboundMessage.fromInput(text);
    } on ArgumentError {
      _lastError = '请先输入要发送的消息。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      try {
        await _channel.invokeMethod<void>('send', {'text': message.text});
        _lastSentMessage = message;
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
    _eventSubscription.cancel();
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

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) {
      return;
    }

    final type = event['type']?.toString();
    switch (type) {
      case 'connected':
        _isConnected = true;
        _statusText = '已连接 ${_selectedDevice?.label ?? ''}'.trim();
      case 'disconnected':
        _isConnected = false;
        _statusText = '已断开';
      case 'received':
        _lastReceivedText = event['text']?.toString() ?? '';
        _statusText = '收到回包';
      case 'error':
        _lastError = event['message']?.toString() ?? '蓝牙错误';
        _statusText = '蓝牙错误';
    }
    notifyListeners();
  }

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message ?? error.code;
    }
    final text = error.toString();
    if (text.contains('permission') || text.contains('BLUETOOTH_CONNECT')) {
      return '需要蓝牙连接权限。';
    }
    if (text.contains('read failed') || text.contains('socket')) {
      return '蓝牙连接中断，请确认 Windows 服务正在运行且手机已配对。';
    }
    return text;
  }
}

class RfcommDebugPage extends StatefulWidget {
  const RfcommDebugPage({super.key, required this.controller});

  final RfcommController controller;

  @override
  State<RfcommDebugPage> createState() => _RfcommDebugPageState();
}

class _RfcommDebugPageState extends State<RfcommDebugPage> {
  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _channelController;

  @override
  void initState() {
    super.initState();
    _channelController = TextEditingController(
      text: widget.controller.rfcommChannel.toString(),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Column(
          children: [
            _StatusBar(controller: controller),
            Expanded(child: _PairedDeviceList(controller: controller)),
            _MessageBar(
              controller: controller,
              messageController: _messageController,
              channelController: _channelController,
            ),
            _RfcommDetailsPanel(controller: controller),
          ],
        );
      },
    );
  }
}

class BleGattDebugPage extends StatefulWidget {
  const BleGattDebugPage({super.key, required this.controller});

  final BleController controller;

  @override
  State<BleGattDebugPage> createState() => _BleGattDebugPageState();
}

class _BleGattDebugPageState extends State<BleGattDebugPage> {
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
        return Column(
          children: [
            _BleStatusBar(controller: controller),
            Expanded(
              child:
                  controller.mode == BleMode.explorer &&
                      controller.explorerCharacteristics.isNotEmpty
                  ? Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _BleDeviceList(controller: controller),
                        ),
                        Expanded(
                          flex: 2,
                          child: _BleCharacteristicList(controller: controller),
                        ),
                      ],
                    )
                  : _BleDeviceList(controller: controller),
            ),
            _BleMessageBar(
              controller: controller,
              messageController: _messageController,
            ),
            _BleDetailsPanel(controller: controller),
          ],
        );
      },
    );
  }
}

class _BleStatusBar extends StatelessWidget {
  const _BleStatusBar({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E7E7))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: controller.isBusy
                    ? null
                    : controller.isScanning
                    ? controller.stopScan
                    : controller.startScan,
                icon: Icon(
                  controller.isScanning
                      ? Icons.stop
                      : Icons.bluetooth_searching,
                  size: 19,
                ),
                label: Text(controller.isScanning ? '停止' : '扫描'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _BleModeTabs(controller: controller)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                key: const ValueKey('ble-toggle-extra-devices'),
                visualDensity: VisualDensity.compact,
                label: Text(
                  controller.mode == BleMode.bridge ? '其它设备' : '无名设备',
                ),
                selected: controller.showAllNamedDevices,
                onSelected: controller.setShowAllNamedDevices,
              ),
              const SizedBox(width: 8),
              Icon(
                controller.isConnected ? Icons.link : Icons.link_off,
                size: 17,
                color: controller.isConnected
                    ? colorScheme.primary
                    : const Color(0xFF6D7776),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  controller.statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BleModeTabs extends StatelessWidget {
  const _BleModeTabs({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DEDD)),
      ),
      child: Row(
        children: [
          _BleModeTab(
            label: 'Bridge',
            selected: controller.mode == BleMode.bridge,
            enabled: !controller.isBusy,
            colorScheme: colorScheme,
            onTap: () => controller.setMode(BleMode.bridge),
          ),
          _BleModeTab(
            label: 'Explorer',
            selected: controller.mode == BleMode.explorer,
            enabled: !controller.isBusy,
            colorScheme: colorScheme,
            onTap: () => controller.setMode(BleMode.explorer),
          ),
        ],
      ),
    );
  }
}

class _BleModeTab extends StatelessWidget {
  const _BleModeTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colorScheme.primary : const Color(0xFF52605E),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BleDeviceList extends StatelessWidget {
  const _BleDeviceList({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    if (devices.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bluetooth_searching, size: 44),
                const SizedBox(height: 12),
                Text(
                  'BLE GATT 调试',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  controller.showAllNamedDevices
                      ? controller.mode == BleMode.bridge
                            ? '还没有扫描到其它有名称设备'
                            : '还没有扫描到设备'
                      : '默认只显示固定 BLE 服务',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final device = devices[index];
        return _BleDeviceTile(
          device: device,
          selected: controller.selectedDevice?.id == device.id,
          connected:
              controller.isConnected &&
              controller.selectedDevice?.id == device.id,
          onTap: () => controller.selectDevice(device),
        );
      },
    );
  }
}

class _BleDeviceTile extends StatelessWidget {
  const _BleDeviceTile({
    required this.device,
    required this.selected,
    required this.connected,
    required this.onTap,
  });

  final BleDeviceInfo device;
  final bool selected;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? colorScheme.primary : const Color(0xFFE3E9E8),
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE0F3EF)
                      : const Color(0xFFE7EFEF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  connected ? Icons.link : Icons.bluetooth,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
              Text(
                '${device.rssi} dBm',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BleCharacteristicList extends StatelessWidget {
  const _BleCharacteristicList({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    final characteristics = controller.explorerCharacteristics;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6E6))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: characteristics.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final characteristic = characteristics[index];
          final selected =
              controller.selectedCharacteristic?.id == characteristic.id;
          return Material(
            key: ValueKey('ble-characteristic-${characteristic.id}'),
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : const Color(0xFFF8FAFA),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => controller.selectCharacteristic(characteristic),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      characteristic.isWritable ? Icons.edit : Icons.visibility,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            characteristic.characteristicUuid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${characteristic.serviceUuid} · ${characteristic.propertiesText}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BleMessageBar extends StatelessWidget {
  const _BleMessageBar({
    required this.controller,
    required this.messageController,
  });

  final BleController controller;
  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6E6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ble-message-input'),
              controller: messageController,
              minLines: 1,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: controller.isConnected
                  ? controller.sendMessage
                  : null,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.short_text, size: 20),
                hintText: selected == null ? '先选择 BLE 设备' : '输入消息',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('ble-send-button'),
            tooltip: controller.isConnected ? '发送' : '请先连接',
            onPressed: controller.isBusy
                ? null
                : () => controller.sendMessage(messageController.text),
            icon: const Icon(Icons.send),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const ValueKey('ble-connect-button'),
            tooltip: controller.isConnected ? '断开 BLE' : '连接 BLE',
            onPressed: selected == null || controller.isBusy
                ? null
                : controller.isConnected
                ? controller.disconnect
                : controller.connectSelected,
            icon: Icon(controller.isConnected ? Icons.link_off : Icons.link),
          ),
        ],
      ),
    );
  }
}

class _BleDetailsPanel extends StatelessWidget {
  const _BleDetailsPanel({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    final sent = controller.lastSentMessage;
    final rows = [
      DetailRowData(label: '状态', value: controller.statusText),
      DetailRowData(
        label: '模式',
        value: controller.mode == BleMode.bridge ? 'Bridge' : 'Explorer',
      ),
      DetailRowData(label: '选中设备', value: selected?.name ?? '无'),
      DetailRowData(label: '设备 ID', value: selected?.id ?? '-'),
      DetailRowData(
        label: '服务 UUID',
        value:
            controller.selectedCharacteristic?.serviceUuid ??
            (controller.mode == BleMode.bridge ? bleBridgeServiceUuid : '-'),
      ),
      DetailRowData(
        label: '特征 UUID',
        value:
            controller.selectedCharacteristic?.characteristicUuid ??
            (controller.mode == BleMode.bridge
                ? bleBridgeCharacteristicUuid
                : '-'),
      ),
      DetailRowData(
        label: '特征属性',
        value: controller.characteristicPropertiesText ?? '-',
      ),
      DetailRowData(label: 'MTU', value: controller.mtu?.toString() ?? '-'),
      DetailRowData(label: 'Service 数量', value: '${controller.serviceCount}'),
      DetailRowData(label: '连接时间', value: controller.connectedAtText ?? '-'),
      DetailRowData(
        label: '最近发送',
        value: sent == null ? '-' : '"${sent.text}" (${sent.byteLength} bytes)',
      ),
      DetailRowData(label: '最近回包', value: controller.lastReceivedText ?? '-'),
      if (controller.lastError != null)
        DetailRowData(label: '错误', value: controller.lastError!),
    ];

    return SharedDetailsPanel(
      connected: controller.isConnected,
      rows: rows,
      compact: true,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final RfcommController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: controller.isBusy
                ? null
                : controller.refreshPairedDevices,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('刷新已配对设备'),
          ),
          const SizedBox(width: 10),
          Icon(
            controller.isConnected ? Icons.link : Icons.link_off,
            color: controller.isConnected
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF7D8887),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              selected == null ? controller.statusText : controller.statusText,
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

class _PairedDeviceList extends StatelessWidget {
  const _PairedDeviceList({required this.controller});

  final RfcommController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '还没有已配对设备',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final device = devices[index];
        return _DeviceTile(
          device: device,
          selected: controller.selectedDevice?.address == device.address,
          connected:
              controller.isConnected &&
              controller.selectedDevice?.address == device.address,
          onTap: () => controller.selectDevice(device),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.connected,
    required this.onTap,
  });

  final PairedBluetoothDevice device;
  final bool selected;
  final bool connected;
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
                  connected ? Icons.computer : Icons.bluetooth,
                  color: selected ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected
                    ? '已连接'
                    : selected
                    ? '已选择'
                    : '已配对',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({
    required this.controller,
    required this.messageController,
    required this.channelController,
  });

  final RfcommController controller;
  final TextEditingController messageController;
  final TextEditingController channelController;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6E6))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('message-input'),
            controller: messageController,
            minLines: 1,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: controller.isConnected ? controller.sendMessage : null,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.edit_note),
              hintText: selected == null ? '先选择 Windows 电脑' : '输入要发送的消息',
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  key: const ValueKey('channel-input'),
                  controller: channelController,
                  enabled: !controller.isConnected && !controller.isBusy,
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    isDense: true,
                    labelText: 'Channel',
                    prefixIcon: Icon(Icons.tag, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  onChanged: controller.setRfcommChannelFromInput,
                ),
              ),
              const Spacer(),
              IconButton.filled(
                tooltip: controller.isConnected ? '发送' : '请先连接',
                onPressed: controller.isBusy
                    ? null
                    : () => controller.sendMessage(messageController.text),
                icon: const Icon(Icons.send),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: selected == null || controller.isBusy
                    ? null
                    : controller.isConnected
                    ? controller.disconnect
                    : controller.connectSelected,
                icon: Icon(
                  controller.isConnected ? Icons.link_off : Icons.link,
                ),
                label: Text(controller.isConnected ? '断开' : '连接'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RfcommDetailsPanel extends StatelessWidget {
  const _RfcommDetailsPanel({required this.controller});

  final RfcommController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    final sent = controller.lastSentMessage;
    final rows = [
      DetailRowData(label: '选中设备', value: selected?.label ?? '无'),
      DetailRowData(label: '设备地址', value: selected?.address ?? '-'),
      const DetailRowData(label: '服务 UUID', value: defaultSppUuid),
      DetailRowData(label: '通道', value: controller.rfcommChannel.toString()),
      DetailRowData(
        label: '最近发送',
        value: sent == null ? '-' : '"${sent.text}" (${sent.byteLength} bytes)',
      ),
      DetailRowData(label: '最近回包', value: controller.lastReceivedText ?? '-'),
      if (controller.lastError != null)
        DetailRowData(label: '错误', value: controller.lastError!),
    ];

    return SharedDetailsPanel(connected: controller.isConnected, rows: rows);
  }
}

class DetailRowData {
  const DetailRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class SharedDetailsPanel extends StatelessWidget {
  const SharedDetailsPanel({
    super.key,
    required this.connected,
    required this.rows,
    this.compact = false,
  });

  final bool connected;
  final List<DetailRowData> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: compact ? 170 : 220),
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 10, 16, compact ? 10 : 14),
      decoration: const BoxDecoration(color: Color(0xFF112624)),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '详情',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: Colors.white),
                  ),
                  const Spacer(),
                  Text(connected ? '已连接' : '未连接'),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              for (final row in rows)
                _DetailLine(label: row.label, value: row.value),
            ],
          ),
        ),
      ),
    );
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
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
