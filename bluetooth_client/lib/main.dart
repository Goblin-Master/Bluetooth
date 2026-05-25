import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rfcomm_helpers.dart';

void main() {
  runApp(const BluetoothClientApp());
}

class BluetoothClientApp extends StatelessWidget {
  const BluetoothClientApp({super.key, this.controller});

  final RfcommController? controller;

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
      ),
    );
  }
}

class BluetoothClientHome extends StatelessWidget {
  const BluetoothClientHome({super.key, required this.rfcommController});

  final RfcommController rfcommController;

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
              const BlePlaceholderPage(),
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

class BlePlaceholderPage extends StatelessWidget {
  const BlePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth_searching, size: 44),
                SizedBox(height: 12),
                Text('BLE GATT 调试', style: TextStyle(fontSize: 20)),
                SizedBox(height: 4),
                Text('待实现'),
              ],
            ),
          ),
        ),
        SharedDetailsPanel(
          connected: false,
          rows: [
            DetailRowData(label: '状态', value: '待实现'),
            DetailRowData(label: '服务 UUID', value: '-'),
            DetailRowData(label: '特征 UUID', value: '-'),
          ],
        ),
      ],
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
  });

  final bool connected;
  final List<DetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
              const SizedBox(height: 8),
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
