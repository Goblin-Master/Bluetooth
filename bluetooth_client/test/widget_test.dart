import 'package:bluetooth_client/ble_helpers.dart';
import 'package:bluetooth_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows BLE bridge controls and devices', (tester) async {
    final controller = FakeBlePageController();
    controller.setDevices([
      const BleDeviceView(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Windows Bridge',
        platformName: 'Windows Bridge',
        advertisedName: 'Bridge Adv',
        rssi: -42,
        signal: '强',
        connectable: true,
      ),
      const BleDeviceView(
        id: 'AA:BB:CC:DD:EE:02',
        name: 'Sensor',
        platformName: 'Sensor',
        advertisedName: 'Sensor Adv',
        rssi: -75,
        signal: '中',
        connectable: true,
      ),
    ]);

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    expect(controller.showUnknown, isFalse);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);
    expect(find.text('BLE 桥接调试'), findsOneWidget);
    expect(find.text('扫描'), findsOneWidget);
    expect(find.text('Windows Bridge'), findsOneWidget);
    expect(find.text('Bridge Adv'), findsNothing);
    expect(find.text('-42 dBm'), findsOneWidget);
    expect(find.text('Sensor'), findsOneWidget);
    expect(find.text('连接蓝牙'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('unknown toggle starts disabled and toggles on tap', (
    tester,
  ) async {
    final controller = FakeBlePageController();

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    expect(controller.showUnknown, isFalse);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.text('显示未知'));
    await tester.pumpAndSettle();

    expect(controller.showUnknown, isTrue);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('selects, connects, and sends a message', (tester) async {
    final controller = FakeBlePageController();
    controller.setDevices([
      const BleDeviceView(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Windows Bridge',
        platformName: 'Windows Bridge',
        advertisedName: 'Bridge Adv',
        rssi: -42,
        signal: '强',
        connectable: true,
      ),
    ]);

    await tester.pumpWidget(BluetoothClientApp(controller: controller));

    await tester.tap(find.text('Windows Bridge'));
    await tester.pump();
    expect(find.textContaining('已选择'), findsWidgets);

    await tester.tap(find.text('连接蓝牙'));
    await tester.pump();
    expect(find.text('断开蓝牙'), findsOneWidget);
    expect(find.text('已连接'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'hello bridge');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(controller.sentMessages, ['hello bridge']);
    expect(find.textContaining('(12 bytes)'), findsOneWidget);
  });

  test('permissions are Android-version aware', () {
    expect(blePermissionNames(30), ['Permission.locationWhenInUse']);
    expect(blePermissionNames(31), [
      'Permission.bluetoothScan',
      'Permission.bluetoothConnect',
    ]);
    expect(blePermissionNames(36), [
      'Permission.bluetoothScan',
      'Permission.bluetoothConnect',
    ]);
  });
}

List<String> blePermissionNames(int sdkInt) {
  return blePermissionsForAndroidSdk(
    sdkInt,
  ).map((permission) => permission.toString()).toList();
}

class FakeBlePageController extends BlePageController {
  bool _isScanning = false;
  final bool _isBusy = false;
  bool _showUnknown = false;
  bool _isConnected = false;
  String _statusText = '就绪';
  String? _lastError;
  List<BleDeviceView> _devices = [];
  BleDeviceView? _selectedDevice;
  BleConnectionDetails _details = const BleConnectionDetails();

  final List<String> sentMessages = [];

  void setDevices(List<BleDeviceView> devices) {
    _devices = devices;
    notifyListeners();
  }

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isBusy => _isBusy;

  @override
  bool get showUnknown => _showUnknown;

  @override
  set showUnknown(bool value) {
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
  List<BleDeviceView> get devices => _devices;

  @override
  BleDeviceView? get selectedDevice => _selectedDevice;

  @override
  BleConnectionDetails get details => _details;

  @override
  Future<void> startScan() async {
    _isScanning = true;
    _statusText = '扫描 10 秒';
    notifyListeners();
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
    _statusText = '已停止扫描';
    notifyListeners();
  }

  @override
  Future<void> selectDevice(BleDeviceView device) async {
    _selectedDevice = device;
    _statusText = '已选择 ${device.name}';
    _lastError = null;
    notifyListeners();
  }

  @override
  Future<void> connectSelected() async {
    if (_selectedDevice == null) {
      _lastError = '请先选择一台 BLE 设备。';
      notifyListeners();
      return;
    }
    _isConnected = true;
    _statusText = '已连接';
    _details = BleConnectionDetails(
      mtu: 247,
      serviceCount: 2,
      writableServiceUuid: '0000ffff-0000-1000-8000-00805f9b34fb',
      writableCharacteristicUuid: '0000ff01-0000-1000-8000-00805f9b34fb',
      writeMode: '有响应写',
      connectedAt: DateTime(2026, 5, 25, 9, 0),
    );
    notifyListeners();
  }

  @override
  Future<void> disconnectSelected() async {
    _isConnected = false;
    _statusText = '已断开';
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _lastError = '请先输入要发送的消息。';
      notifyListeners();
      return;
    }
    sentMessages.add(trimmed);
    _statusText = '已发送';
    _details = BleConnectionDetails(
      mtu: _details.mtu,
      serviceCount: _details.serviceCount,
      writableServiceUuid: _details.writableServiceUuid,
      writableCharacteristicUuid: _details.writableCharacteristicUuid,
      writeMode: _details.writeMode,
      connectedAt: _details.connectedAt,
      lastSentText: trimmed,
      lastSentBytes: trimmed.length,
      lastSentAt: DateTime(2026, 5, 25, 9, 1),
    );
    notifyListeners();
  }
}
