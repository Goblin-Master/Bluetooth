# bluetooth_server

Windows Python Bluetooth echo server for the Flutter Android client.

Run this on Windows Python, not WSL.

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

BLE GATT uses Windows WinRT to expose a local GATT service:

```powershell
uv run bt-server --mode ble
```

Run both:

```powershell
uv run bt-server --mode both --channel 4
```

There is no `--ble-name` option now. The BLE bridge is identified by UUIDs, not by a configurable advertised name.

## BLE UUIDs

```text
Service UUID:        12345678-1234-5678-1234-56789abcdef0
Characteristic UUID: 12345678-1234-5678-1234-56789abcdef1
```

The Service UUID identifies the bridge service during BLE scan and service discovery. The Characteristic UUID identifies the message endpoint under that service. The characteristic supports read, write, write without response, and notify.

Data flow:

```text
Flutter writes UTF-8 text -> Characteristic write event
Windows prints message -> stores Echo response -> sends notify
Flutter receives notify -> details panel shows recent reply
```

## Common Issues

- If RFCOMM channel `4` is busy, use `--channel 5` and set the same value in the app.
- If RFCOMM cannot connect, confirm phone and Windows are paired in system Bluetooth settings.
- If BLE cannot advertise, confirm Windows Bluetooth is enabled and no other bridge process is already running.
- If the app shows `Unknown` and the PC name for the same bridge, use the named row. The client hides the unknown bridge duplicate once a named bridge is available.
- If Explorer can write to another device but gets no useful reply, that device probably does not speak this repo's plain UTF-8 echo protocol.

## Test

```powershell
uv run python -m unittest discover tests
```
