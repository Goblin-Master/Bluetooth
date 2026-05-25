import 'package:bluetooth_client/rfcomm_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes paired device names', () {
    expect(displayBluetoothName('Windows PC', 'AA:BB'), 'Windows PC');
    expect(displayBluetoothName('', 'AA:BB'), 'AA:BB');
    expect(displayBluetoothName(null, 'AA:BB'), 'AA:BB');
  });

  test('sorts paired devices by name and address', () {
    final devices = [
      const PairedBluetoothDevice(address: '22:22', name: 'Phone'),
      const PairedBluetoothDevice(address: '11:11', name: 'Windows PC'),
      const PairedBluetoothDevice(address: '33:33', name: ''),
    ]..sort(comparePairedDevices);

    expect(devices.map((device) => device.label), [
      '33:33',
      'Phone',
      'Windows PC',
    ]);
  });

  test('trims outbound messages and encodes UTF-8 byte length', () {
    final message = OutboundMessage.fromInput('  hello  ');

    expect(message.text, 'hello');
    expect(message.byteLength, 5);
  });

  test('rejects empty outbound messages', () {
    expect(() => OutboundMessage.fromInput('   '), throwsArgumentError);
  });

  test('normalizes RFCOMM channel input', () {
    expect(normalizeRfcommChannel('1'), 1);
    expect(normalizeRfcommChannel(' 30 '), 30);
  });

  test('rejects invalid RFCOMM channels', () {
    expect(() => normalizeRfcommChannel('0'), throwsArgumentError);
    expect(() => normalizeRfcommChannel('31'), throwsArgumentError);
    expect(() => normalizeRfcommChannel('abc'), throwsArgumentError);
  });
}
