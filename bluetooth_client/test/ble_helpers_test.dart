import 'package:bluetooth_client/ble_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines fixed BLE bridge identity', () {
    expect(defaultBleBridgeName, 'BluetoothTestBridge');
    expect(bleBridgeServiceUuid, '12345678-1234-5678-1234-56789abcdef0');
    expect(bleBridgeCharacteristicUuid, '12345678-1234-5678-1234-56789abcdef1');
  });

  test('filters named devices by default and can show all named devices', () {
    final devices = [
      const BleDeviceInfo(id: '1', name: 'Unknown', rssi: -30),
      const BleDeviceInfo(id: '2', name: 'BluetoothTestBridge', rssi: -80),
      const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
      const BleDeviceInfo(id: '4', name: '', rssi: -20),
    ];

    expect(filterBleDevices(devices, showAllNamedDevices: false), [
      const BleDeviceInfo(id: '2', name: 'BluetoothTestBridge', rssi: -80),
    ]);
    expect(filterBleDevices(devices, showAllNamedDevices: true), [
      const BleDeviceInfo(id: '2', name: 'BluetoothTestBridge', rssi: -80),
      const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
    ]);
  });

  test('sorts BLE bridge first then by strongest RSSI', () {
    final devices = [
      const BleDeviceInfo(id: '1', name: 'Sensor', rssi: -20),
      const BleDeviceInfo(id: '2', name: 'BluetoothTestBridge', rssi: -90),
      const BleDeviceInfo(id: '3', name: 'Beacon', rssi: -40),
    ]..sort(compareBleDevices);

    expect(devices.map((device) => device.id), ['2', '1', '3']);
  });
}
