import 'package:bluetooth_client/main.dart';
import 'package:bluetooth_client/ble_helpers.dart';
import 'package:bluetooth_client/rfcomm_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows paired RFCOMM devices and send controls', (tester) async {
    final controller = FakeRfcommController();
    controller.setDevices([
      const PairedBluetoothDevice(
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Windows PC',
      ),
      const PairedBluetoothDevice(address: 'AA:BB:CC:DD:EE:02', name: 'Phone'),
    ]);

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    expect(find.text('Bluetooth 调试'), findsOneWidget);
    expect(find.text('RFCOMM'), findsOneWidget);
    expect(find.text('BLE'), findsOneWidget);
    expect(find.text('刷新已配对设备'), findsOneWidget);
    expect(find.text('Windows PC'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:01'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Channel'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('selects, connects, sends, and disconnects', (tester) async {
    final controller = FakeRfcommController();
    controller.setDevices([
      const PairedBluetoothDevice(
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Windows PC',
      ),
    ]);

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    await tester.tap(find.text('Windows PC'));
    await tester.pump();
    expect(find.textContaining('已选择'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('channel-input')), '2');
    await tester.tap(find.text('连接'));
    await tester.pump();
    expect(find.text('断开'), findsOneWidget);
    expect(find.textContaining('已连接'), findsWidgets);
    expect(controller.lastConnectedChannel, 2);

    await tester.enterText(
      find.byKey(const ValueKey('message-input')),
      'hello windows',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(controller.sentMessages, ['hello windows']);
    expect(find.textContaining('Echo: hello windows'), findsOneWidget);

    await tester.tap(find.text('断开'));
    await tester.pump();
    expect(find.text('连接'), findsOneWidget);
  });

  testWidgets('shows a clear error when sending before connection', (
    tester,
  ) async {
    final controller = FakeRfcommController();

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    await tester.enterText(
      find.byKey(const ValueKey('message-input')),
      'hello',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.textContaining('请先连接'), findsOneWidget);
  });

  testWidgets('shows long error details without truncating them', (
    tester,
  ) async {
    const longError =
        'Need android.permission.BLUETOOTH_SCAN permission for android.content.AttributionSource@123';
    final controller = FakeRfcommController()..setError(longError);

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    final errorText = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == longError,
      ),
    );
    expect(errorText.maxLines, isNull);
  });

  testWidgets('shows BLE placeholder tab', (tester) async {
    final bleController = FakeBleController();

    await tester.pumpWidget(
      BluetoothClientApp(
        controller: FakeRfcommController(),
        bleController: bleController,
      ),
    );
    await tester.tap(find.text('BLE'));
    await tester.pumpAndSettle();

    expect(find.text('BLE GATT 调试'), findsOneWidget);
    expect(find.text('扫描'), findsOneWidget);
    expect(find.text('BluetoothTestBridge'), findsNothing);
  });

  testWidgets('BLE tab scans, selects, connects, sends, and disconnects', (
    tester,
  ) async {
    final bleController = FakeBleController();
    bleController.setDevices([
      const BleDeviceInfo(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Windows PC',
        rssi: -35,
        advertisesBridgeService: true,
      ),
      const BleDeviceInfo(id: 'AA:BB:CC:DD:EE:02', name: 'Sensor', rssi: -20),
    ]);

    await tester.pumpWidget(
      BluetoothClientApp(
        controller: FakeRfcommController(),
        bleController: bleController,
      ),
    );
    await tester.tap(find.text('BLE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫描'));
    await tester.pump();
    expect(find.text('Windows PC'), findsOneWidget);
    expect(find.textContaining('-35 dBm'), findsOneWidget);
    expect(find.text('Sensor'), findsNothing);

    await tester.tap(find.text('显示全部'));
    await tester.pump();
    expect(find.text('Sensor'), findsOneWidget);

    await tester.tap(find.text('Windows PC'));
    await tester.pump();
    expect(find.textContaining('已选择'), findsWidgets);

    await tester.tap(find.text('连接 BLE'));
    await tester.pump();
    expect(find.text('断开 BLE'), findsOneWidget);
    expect(find.textContaining(bleBridgeServiceUuid), findsOneWidget);
    expect(find.textContaining('writeWithoutResponse'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ble-message-input')),
      'hello ble',
    );
    await tester.tap(find.byKey(const ValueKey('ble-send-button')));
    await tester.pump();
    expect(bleController.sentMessages, ['hello ble']);
    expect(find.textContaining('Echo: hello ble'), findsOneWidget);

    await tester.tap(find.text('断开 BLE'));
    await tester.pump();
    expect(find.text('连接 BLE'), findsOneWidget);
  });
}

class FakeRfcommController extends RfcommController {
  final bool _isBusy = false;
  bool _isConnected = false;
  String _statusText = '就绪';
  String? _lastError;
  String? _lastReceivedText;
  OutboundMessage? _lastSentMessage;
  List<PairedBluetoothDevice> _devices = [];
  PairedBluetoothDevice? _selectedDevice;

  final List<String> sentMessages = [];
  int channel = defaultRfcommChannel;
  int? lastConnectedChannel;

  void setDevices(List<PairedBluetoothDevice> devices) {
    _devices = devices;
    notifyListeners();
  }

  void setError(String error) {
    _lastError = error;
    notifyListeners();
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
  int get rfcommChannel => channel;

  @override
  List<PairedBluetoothDevice> get devices => _devices;

  @override
  PairedBluetoothDevice? get selectedDevice => _selectedDevice;

  @override
  void setRfcommChannelFromInput(String input) {
    try {
      channel = normalizeRfcommChannel(input);
      _lastError = null;
    } on ArgumentError {
      _lastError = 'RFCOMM channel 必须是 1-30。';
    }
    notifyListeners();
  }

  @override
  Future<void> refreshPairedDevices() async {
    _statusText = _devices.isEmpty ? '没有已配对设备' : '已加载 ${_devices.length} 台';
    notifyListeners();
  }

  @override
  Future<void> selectDevice(PairedBluetoothDevice device) async {
    _selectedDevice = device;
    _statusText = '已选择 ${device.label}';
    _lastError = null;
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    if (_selectedDevice == null) {
      _lastError = '请先选择 Windows 电脑。';
      notifyListeners();
      return;
    }
    _isConnected = true;
    lastConnectedChannel = channel;
    _statusText = '已连接 ${_selectedDevice!.label}';
    _lastError = null;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _statusText = '已断开';
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String text) async {
    if (!_isConnected) {
      _lastError = '请先连接 Windows RFCOMM 服务。';
      notifyListeners();
      return;
    }
    _lastSentMessage = OutboundMessage.fromInput(text);
    sentMessages.add(_lastSentMessage!.text);
    _lastReceivedText = 'Echo: ${_lastSentMessage!.text}';
    _statusText = '已发送';
    notifyListeners();
  }
}

class FakeBleController extends BleController {
  final bool _isBusy = false;
  bool _isScanning = false;
  bool _isConnected = false;
  bool _showAllNamedDevices = false;
  String _statusText = '就绪';
  String? _lastError;
  String? _lastReceivedText;
  OutboundMessage? _lastSentMessage;
  BleDeviceInfo? _selectedDevice;
  List<BleDeviceInfo> _devices = [];
  int? _mtu;
  int _serviceCount = 0;
  String? _connectedAtText;
  String? _characteristicPropertiesText;

  final List<String> sentMessages = [];

  void setDevices(List<BleDeviceInfo> devices) {
    _devices = devices;
    notifyListeners();
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
  String get statusText => _statusText;

  @override
  String? get lastError => _lastError;

  @override
  String? get lastReceivedText => _lastReceivedText;

  @override
  OutboundMessage? get lastSentMessage => _lastSentMessage;

  @override
  BleDeviceInfo? get selectedDevice => _selectedDevice;

  @override
  List<BleDeviceInfo> get devices =>
      filterBleDevices(_devices, showAllNamedDevices: _showAllNamedDevices);

  @override
  int? get mtu => _mtu;

  @override
  int get serviceCount => _serviceCount;

  @override
  String? get connectedAtText => _connectedAtText;

  @override
  String? get characteristicPropertiesText => _characteristicPropertiesText;

  @override
  void setShowAllNamedDevices(bool value) {
    _showAllNamedDevices = value;
    notifyListeners();
  }

  @override
  Future<void> startScan() async {
    _isScanning = true;
    _statusText = '扫描中';
    notifyListeners();
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
    _statusText = '已停止扫描';
    notifyListeners();
  }

  @override
  Future<void> selectDevice(BleDeviceInfo device) async {
    _selectedDevice = device;
    _statusText = '已选择 ${device.name}';
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    if (_selectedDevice == null) {
      _lastError = '请先选择 BLE 设备。';
      notifyListeners();
      return;
    }
    _isConnected = true;
    _isScanning = false;
    _mtu = 512;
    _serviceCount = 1;
    _connectedAtText = '12:00:00';
    _characteristicPropertiesText = 'read, writeWithoutResponse, notify';
    _statusText = '已连接 ${_selectedDevice!.name}';
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _characteristicPropertiesText = null;
    _statusText = '已断开';
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String text) async {
    _lastSentMessage = OutboundMessage.fromInput(text);
    sentMessages.add(_lastSentMessage!.text);
    _lastReceivedText = 'Echo: ${_lastSentMessage!.text}';
    _statusText = '已发送';
    notifyListeners();
  }
}
