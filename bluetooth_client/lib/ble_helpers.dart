import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

const unknownDeviceName = '未知设备';

class WritableTarget {
  const WritableTarget({
    required this.characteristic,
    required this.withoutResponse,
  });

  final BluetoothCharacteristic characteristic;
  final bool withoutResponse;

  String get serviceUuid => characteristic.serviceUuid.toString();
  String get characteristicUuid => characteristic.characteristicUuid.toString();
}

List<Permission> blePermissionsForAndroidSdk(int sdkInt) {
  if (sdkInt >= 31) {
    return [Permission.bluetoothScan, Permission.bluetoothConnect];
  }

  return [Permission.locationWhenInUse];
}

WritableTarget? findWritableTarget(List<BluetoothService> services) {
  for (final service in services) {
    for (final characteristic in service.characteristics) {
      final properties = characteristic.properties;
      if (properties.write) {
        return WritableTarget(
          characteristic: characteristic,
          withoutResponse: false,
        );
      }
    }
  }

  for (final service in services) {
    for (final characteristic in service.characteristics) {
      final properties = characteristic.properties;
      if (properties.writeWithoutResponse) {
        return WritableTarget(
          characteristic: characteristic,
          withoutResponse: true,
        );
      }
    }
  }

  return null;
}

String displayDeviceName(ScanResult result) {
  return chooseDisplayDeviceName(
    platformName: result.device.platformName,
    advName: result.advertisementData.advName,
  );
}

String chooseDisplayDeviceName({
  required String platformName,
  required String advName,
}) {
  final normalizedPlatformName = platformName.trim();
  if (normalizedPlatformName.isNotEmpty) {
    return normalizedPlatformName;
  }

  final normalizedAdvName = advName.trim();
  if (normalizedAdvName.isNotEmpty) {
    return normalizedAdvName;
  }

  return unknownDeviceName;
}

bool shouldShowScanResult(ScanResult result, {required bool showUnknown}) {
  if (showUnknown) {
    return true;
  }

  final name = displayDeviceName(result);
  return name != unknownDeviceName;
}

String signalLabel(int rssi) {
  if (rssi >= -60) {
    return '强';
  }
  if (rssi >= -80) {
    return '中';
  }
  return '弱';
}

int compareScanResultsBySignal(ScanResult a, ScanResult b) {
  final byRssi = b.rssi.compareTo(a.rssi);
  if (byRssi != 0) {
    return byRssi;
  }
  return displayDeviceName(a).compareTo(displayDeviceName(b));
}
