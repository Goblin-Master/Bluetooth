# bluetooth_server

Windows Python Bluetooth echo server for the Flutter Android client.

## Setup

Run in Windows PowerShell:

```powershell
uv sync
```

## Modes

RFCOMM uses Bluetooth Classic. Pair the phone with Windows first in system settings, then keep the channel matched with the Flutter RFCOMM tab.

```powershell
uv run bt-server --mode rfcomm --channel 4
```

BLE GATT exposes the fixed bridge service UUID through Windows WinRT:

```powershell
uv run bt-server --mode ble
```

Run both:

```powershell
uv run bt-server --mode both --channel 4 --ble-name BluetoothTestBridge
```

BLE UUIDs:

```text
Service:        12345678-1234-5678-1234-56789abcdef0
Characteristic: 12345678-1234-5678-1234-56789abcdef1
```

The characteristic supports read, write, and notify. Writes are decoded as UTF-8 and echoed as `Echo: ...`.

## Common Issues

- Run this on Windows Python, not WSL.
- If RFCOMM channel 4 is busy, use `--channel 5` and set the same value in the app.
- If BLE cannot advertise, confirm Windows Bluetooth is enabled and no other bridge process is already running.
- The Flutter client scans for the fixed BLE service UUID, so the Windows device name shown in scan results may be your PC name instead of `BluetoothTestBridge`.

## Test

```powershell
uv run python -m unittest discover tests
```
