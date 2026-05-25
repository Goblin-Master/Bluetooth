# bluetooth_server

Windows Bluetooth Classic RFCOMM echo server for the Flutter Android client.

Run on Windows PowerShell after pairing the phone with the PC:

```powershell
uv run bt-server
```

If channel 1 is busy:

```powershell
uv run bt-server --channel 2
```
