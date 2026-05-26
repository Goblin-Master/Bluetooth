import 'package:flutter/foundation.dart';

const bleBridgeServiceUuid = '12345678-1234-5678-1234-56789abcdef0';
const bleBridgeCharacteristicUuid = '12345678-1234-5678-1234-56789abcdef1';
const List<String> defaultBleScanServiceFilters = [];

enum BleMode { bridge, explorer }

enum BleWriteMode { withResponse, withoutResponse, unsupported }

bool shouldRequestBleRuntimePermissions({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb && platform == TargetPlatform.android;
}

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

List<BleDeviceInfo> filterExplorerDevices(
  Iterable<BleDeviceInfo> devices, {
  required bool showUnnamedDevices,
}) {
  final filtered = devices.where((device) {
    return showUnnamedDevices || device.hasUsableName;
  }).toList()..sort(compareBleDevicesBySignal);
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

int compareBleDevicesBySignal(BleDeviceInfo a, BleDeviceInfo b) {
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

class BleCharacteristicInfo {
  const BleCharacteristicInfo({
    required this.id,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.propertiesText,
    required this.canWrite,
    required this.canWriteWithoutResponse,
  });

  final String id;
  final String serviceUuid;
  final String characteristicUuid;
  final String propertiesText;
  final bool canWrite;
  final bool canWriteWithoutResponse;

  bool get isWritable => canWrite || canWriteWithoutResponse;

  @override
  bool operator ==(Object other) {
    return other is BleCharacteristicInfo &&
        other.id == id &&
        other.serviceUuid == serviceUuid &&
        other.characteristicUuid == characteristicUuid &&
        other.propertiesText == propertiesText &&
        other.canWrite == canWrite &&
        other.canWriteWithoutResponse == canWriteWithoutResponse;
  }

  @override
  int get hashCode => Object.hash(
    id,
    serviceUuid,
    characteristicUuid,
    propertiesText,
    canWrite,
    canWriteWithoutResponse,
  );
}
