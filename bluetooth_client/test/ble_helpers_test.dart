import 'package:bluetooth_client/ble_helpers.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hides unknown devices unless showUnknown is enabled', () {
    final result = ScanResult(
      device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
      advertisementData: AdvertisementData(
        advName: '',
        txPowerLevel: null,
        appearance: null,
        connectable: true,
        manufacturerData: const {},
        serviceData: const {},
        serviceUuids: const [],
      ),
      rssi: -45,
      timeStamp: DateTime(2026, 5, 25),
    );

    expect(shouldShowScanResult(result, showUnknown: false), isFalse);
    expect(shouldShowScanResult(result, showUnknown: true), isTrue);
  });
}
