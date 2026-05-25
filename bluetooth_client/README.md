# bluetooth_client

Android Flutter client for Bluetooth Classic RFCOMM and BLE GATT testing.

Run from WSL:

```bash
flutter pub get
flutter run -d 192.168.2.181:40273
```

Tabs:

- `RFCOMM`: lists already paired Bluetooth devices. Pair the phone with the Windows PC first, then match the channel with `bt-server`.
- `BLE`: scans for the fixed bridge GATT service, connects, writes text, and shows echo notifications.

BLE UUIDs:

```text
Service:        12345678-1234-5678-1234-56789abcdef0
Characteristic: 12345678-1234-5678-1234-56789abcdef1
```

Verify locally:

```bash
flutter test
flutter analyze
flutter build apk --debug
```
