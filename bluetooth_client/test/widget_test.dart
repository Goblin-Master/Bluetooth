import 'package:bluetooth_client/main.dart';
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
    final controller = FakeRfcommController();

    await tester.pumpWidget(BluetoothClientApp(controller: controller));
    await tester.tap(find.text('BLE'));
    await tester.pumpAndSettle();

    expect(find.text('BLE GATT 调试'), findsOneWidget);
    expect(find.text('待实现'), findsWidgets);
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
