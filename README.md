# Bluetooth

Flutter Android client + Windows Python Bluetooth test bridge.

## Goal

This project verifies two small phone-to-Windows Bluetooth paths:

```text
RFCOMM:
Flutter Android App -> Bluetooth Classic RFCOMM -> Windows Python Server

BLE GATT:
Flutter Android App -> BLE GATT write -> Windows Python bless Server
```

两条链路现在都只做 echo 调试，不做 Wi-Fi 配网写入，也不接 Go 后端。RFCOMM 用系统配对设备和 channel；BLE GATT 用固定广播名 `BluetoothTestBridge`、固定 Service UUID 和 Characteristic UUID。

## 目录结构

```text
.
├── bluetooth_client/        # Flutter Android RFCOMM + BLE GATT client
├── bluetooth_server/        # Windows Python RFCOMM + bless BLE server, managed by uv
├── install_flutter_android_wsl.sh
└── install_uv_windows.ps1
```

## WSL Flutter 环境

WSL 脚本只安装 Flutter、Android SDK、JDK 和必要 Linux 依赖：

```bash
chmod +x ./install_flutter_android_wsl.sh
./install_flutter_android_wsl.sh
```

如果要换安装目录：

```bash
FLUTTER_DIR=$HOME/tools/flutter ANDROID_SDK_ROOT=$HOME/Android/Sdk ./install_flutter_android_wsl.sh
```

默认启用国内镜像；如果要使用官方源：

```bash
NO_CHINA_MIRRORS=1 ./install_flutter_android_wsl.sh
```

安装后：

```bash
source ~/.bashrc
flutter doctor --android-licenses
adb devices
flutter devices
```

你的真机无线调试设备如果出现两个入口，优先用明确 IP 的那个：

```bash
flutter run -d 192.168.2.181:40273
```

## Windows Python 环境

Windows 上安装 uv 和 Python：

```powershell
powershell -ExecutionPolicy Bypass -File .\install_uv_windows.ps1
```

然后在 Windows 设置里完成：

```text
Settings -> Bluetooth & devices -> Pair phone with this PC
```

## 启动服务端

在 Windows PowerShell 里运行：

```powershell
cd bluetooth_server
uv sync
```

RFCOMM only:

```powershell
uv run bt-server --mode rfcomm --channel 4
```

BLE GATT only:

```powershell
uv run bt-server --mode ble
```

Both:

```powershell
uv run bt-server --mode both --channel 4 --ble-name BluetoothTestBridge
```

默认 RFCOMM channel 是 `4`。如果被占用：

```powershell
uv run bt-server --channel 5
```

App 里的 RFCOMM `Channel` 输入框要和服务端 channel 保持一致。服务端必须跑在 Windows Python 上，不要跑在 WSL 里；WSL 不能直接拿到 Windows 蓝牙控制器。

## 启动 Flutter 客户端

在 WSL 里运行：

```bash
cd bluetooth_client
flutter pub get
flutter run -d 192.168.2.181:40273
```

App 内 RFCOMM 操作：

1. 点击“刷新已配对设备”。
2. 选择 Windows 电脑。
3. 确认 `Channel` 和 Windows 服务端一致，默认都是 4。
4. 点击“连接”。
5. 输入文本并点击发送。
6. 下方详情区查看最近发送和 Windows 服务端回包。

App 内 BLE GATT 操作：

1. Windows PowerShell 启动 `uv run bt-server --mode ble` 或 `--mode both`。
2. Flutter App 切到 `BLE` tab。
3. 点击“扫描”，默认只显示 `BluetoothTestBridge`。
4. 选择设备，点击“连接 BLE”。
5. 输入文本并发送。
6. 下方详情区查看固定 UUID、MTU、service 数量、最近回包和完整错误。

## 测试

Flutter：

```bash
cd bluetooth_client
flutter test
flutter analyze
flutter build apk --debug
```

Python 服务端：

```bash
cd bluetooth_server
uv run python -m unittest discover tests
```
