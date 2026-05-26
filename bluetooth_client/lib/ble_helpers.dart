const bleBridgeServiceUuid = '12345678-1234-5678-1234-56789abcdef0';
const bleBridgeCharacteristicUuid = '12345678-1234-5678-1234-56789abcdef1';
const List<String> defaultBleScanServiceFilters = [];

enum BleWriteMode { withResponse, withoutResponse, unsupported }

BleWriteMode selectBleWriteMode({
  required bool canWrite,
  required bool canWriteWithoutResponse,
}) {
  if (canWrite) {
    return BleWriteMode.withResponse;
  }
  if (canWriteWithoutResponse) {
    return BleWriteMode.withoutResponse;
  }
  return BleWriteMode.unsupported;
}

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
    this.advertisesBridgeService = false,
  });

  final String id;
  final String name;
  final int rssi;
  final bool advertisesBridgeService;

  bool get isBridge => advertisesBridgeService;
  bool get hasUsableName => name.trim().isNotEmpty && name.trim() != 'Unknown';

  @override
  bool operator ==(Object other) {
    return other is BleDeviceInfo &&
        other.id == id &&
        other.name == name &&
        other.rssi == rssi &&
        other.advertisesBridgeService == advertisesBridgeService;
  }

  @override
  int get hashCode => Object.hash(id, name, rssi, advertisesBridgeService);
}

List<BleDeviceInfo> filterBleDevices(
  Iterable<BleDeviceInfo> devices, {
  required bool showAllNamedDevices,
}) {
  final deviceList = devices.toList();
  final hasNamedBridge = deviceList.any(
    (device) => device.isBridge && device.hasUsableName,
  );
  final filtered = deviceList.where((device) {
    if (hasNamedBridge && device.isBridge && !device.hasUsableName) {
      return false;
    }
    if (device.isBridge) {
      return true;
    }
    return showAllNamedDevices && device.hasUsableName;
  }).toList()..sort(compareBleDevices);
  return filtered;
}

int compareBleDevices(BleDeviceInfo a, BleDeviceInfo b) {
  if (a.isBridge != b.isBridge) {
    return a.isBridge ? -1 : 1;
  }
  final byRssi = b.rssi.compareTo(a.rssi);
  if (byRssi != 0) {
    return byRssi;
  }
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) {
    return byName;
  }
  return a.id.compareTo(b.id);
}
