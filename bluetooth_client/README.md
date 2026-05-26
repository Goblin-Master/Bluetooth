# bluetooth_client

Android Flutter client for Bluetooth Classic RFCOMM and BLE GATT testing.

Run from WSL:

```bash
flutter pub get
flutter run -d 192.168.2.181:42091
```

Use the device id from `flutter devices`; the wireless debug port changes often.

## RFCOMM Tab

RFCOMM lists Android system paired Bluetooth devices. Pair the phone with the Windows PC first, then start the Windows server with the same channel:

```powershell
uv run bt-server --mode rfcomm --channel 4
```

The app uses the standard SPP UUID first:

```text
00001101-0000-1000-8000-00805F9B34FB
```

If that fails, the Android native layer falls back to the channel number entered in the UI. Keep the UI `Channel` value matched with `--channel`.

## BLE Tab

The BLE tab has two modes.

### Bridge

Bridge mode is for this repo's Windows Python WinRT GATT server:

```powershell
uv run bt-server --mode ble
```

Fixed UUIDs:

```text
Service UUID:        12345678-1234-5678-1234-56789abcdef0
Characteristic UUID: 12345678-1234-5678-1234-56789abcdef1
```

Roles:

- `Service UUID`: identifies the bridge service in BLE advertisements. Bridge mode treats devices advertising this UUID as bridge candidates.
- `Characteristic UUID`: identifies the message pipe after connection and service discovery. The app writes UTF-8 text to it and listens for notify echo data.

Display and lookup rules:

- BLE scan starts without platform service filters, so the app can also show nearby non-bridge devices when requested.
- Bridge mode defaults to devices advertising the fixed Service UUID.
- If a named bridge and an `Unknown` bridge duplicate appear, the `Unknown` row is hidden.
- “其它设备” shows named non-bridge devices too.
- Devices are sorted by bridge first, then strongest RSSI first.
- After connect, Bridge mode looks for the fixed Characteristic UUID under the fixed Service UUID.

### Explorer

Explorer mode is a generic BLE browser:

- It does not assume the fixed bridge UUIDs.
- It defaults to named BLE devices; “无名设备” includes `Unknown`.
- After connect, it discovers all services and characteristics.
- It auto-selects the first writable characteristic.
- You can manually select another characteristic.

Writable BLE characteristics may still reject or ignore plain text if the device expects a private binary protocol, authentication, pairing, checksum, or a different write mode.

## Verify Locally

```bash
flutter test
flutter analyze
flutter build apk --debug
```
