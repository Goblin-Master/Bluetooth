import 'package:bluetooth_client/ble_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines fixed BLE GATT identity', () {
    expect(bleBridgeServiceUuid, '12345678-1234-5678-1234-56789abcdef0');
    expect(bleBridgeCharacteristicUuid, '12345678-1234-5678-1234-56789abcdef1');
  });

  test(
    'filters advertised bridge service by default and can show named devices',
    () {
      final devices = [
        const BleDeviceInfo(id: '1', name: 'Unknown', rssi: -30),
        const BleDeviceInfo(
          id: '2',
          name: 'Windows PC',
          rssi: -80,
          advertisesBridgeService: true,
        ),
        const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
        const BleDeviceInfo(id: '4', name: '', rssi: -20),
      ];

      expect(filterBleDevices(devices, showAllNamedDevices: false), [
        const BleDeviceInfo(
          id: '2',
          name: 'Windows PC',
          rssi: -80,
          advertisesBridgeService: true,
        ),
      ]);
      expect(filterBleDevices(devices, showAllNamedDevices: true), [
        const BleDeviceInfo(
          id: '2',
          name: 'Windows PC',
          rssi: -80,
          advertisesBridgeService: true,
        ),
        const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
      ]);
    },
  );

  test('treats advertised bridge service as the BLE bridge', () {
    const device = BleDeviceInfo(
      id: '1',
      name: 'Windows PC',
      rssi: -50,
      advertisesBridgeService: true,
    );

    expect(device.isBridge, isTrue);
    expect(filterBleDevices([device], showAllNamedDevices: false), [device]);
  });

  test('hides unknown bridge when a named bridge is available', () {
    final devices = [
      const BleDeviceInfo(
        id: '1',
        name: 'Unknown',
        rssi: -44,
        advertisesBridgeService: true,
      ),
      const BleDeviceInfo(
        id: '2',
        name: 'LP-A0113',
        rssi: -49,
        advertisesBridgeService: true,
      ),
    ];

    expect(filterBleDevices(devices, showAllNamedDevices: false), [
      const BleDeviceInfo(
        id: '2',
        name: 'LP-A0113',
        rssi: -49,
        advertisesBridgeService: true,
      ),
    ]);
  });

  test('keeps unknown bridge when it is the only bridge result', () {
    const device = BleDeviceInfo(
      id: '1',
      name: 'Unknown',
      rssi: -44,
      advertisesBridgeService: true,
    );

    expect(filterBleDevices([device], showAllNamedDevices: false), [device]);
  });

  test('does not use service filters for default BLE scan', () {
    expect(defaultBleScanServiceFilters, isEmpty);
  });

  test('filters explorer devices independently from bridge UUID', () {
    final devices = [
      const BleDeviceInfo(id: '1', name: 'Unknown', rssi: -30),
      const BleDeviceInfo(
        id: '2',
        name: 'Windows PC',
        rssi: -80,
        advertisesBridgeService: true,
      ),
      const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
    ];

    expect(filterExplorerDevices(devices, showUnnamedDevices: false), [
      const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
      const BleDeviceInfo(
        id: '2',
        name: 'Windows PC',
        rssi: -80,
        advertisesBridgeService: true,
      ),
    ]);
    expect(filterExplorerDevices(devices, showUnnamedDevices: true), [
      const BleDeviceInfo(id: '1', name: 'Unknown', rssi: -30),
      const BleDeviceInfo(id: '3', name: 'Sensor', rssi: -40),
      const BleDeviceInfo(
        id: '2',
        name: 'Windows PC',
        rssi: -80,
        advertisesBridgeService: true,
      ),
    ]);
  });

  test('selects BLE write mode from characteristic properties', () {
    expect(
      selectBleWriteMode(canWrite: true, canWriteWithoutResponse: true),
      BleWriteMode.withResponse,
    );
    expect(
      selectBleWriteMode(canWrite: false, canWriteWithoutResponse: true),
      BleWriteMode.withoutResponse,
    );
    expect(
      selectBleWriteMode(canWrite: false, canWriteWithoutResponse: false),
      BleWriteMode.unsupported,
    );
  });

  test('sorts BLE bridge first then by strongest RSSI', () {
    final devices = [
      const BleDeviceInfo(id: '1', name: 'Sensor', rssi: -20),
      const BleDeviceInfo(
        id: '2',
        name: 'Windows PC',
        rssi: -90,
        advertisesBridgeService: true,
      ),
      const BleDeviceInfo(id: '3', name: 'Beacon', rssi: -40),
    ]..sort(compareBleDevices);

    expect(devices.map((device) => device.id), ['2', '1', '3']);
  });
}
