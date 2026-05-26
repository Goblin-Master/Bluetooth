# Bluetooth

Flutter Bluetooth client + Windows Python Bluetooth test bridge.

## Goal

这个项目用来验证手机到 Windows 电脑的两条蓝牙调试链路：

```text
RFCOMM:
Flutter Android App -> Bluetooth Classic RFCOMM -> Windows Python socket server

BLE GATT:
Flutter App -> BLE GATT write/read/notify -> Windows Python WinRT GATT server
```

两条链路现在都只做 echo 调试，不做 Wi-Fi 配网写入，也不接 Go 后端。RFCOMM 是当前 Android 原生桥接实现；BLE 使用 `flutter_blue_plus`，客户端逻辑不再限制 Android。服务端必须跑在 Windows Python 上，WSL 不能直接拿到 Windows 蓝牙控制器。

## Project Layout

```text
.
├── bluetooth_client/        # Flutter RFCOMM + BLE GATT client
├── bluetooth_server/        # Windows Python RFCOMM + WinRT BLE server, managed by uv
├── install_flutter_android_wsl.sh
└── install_uv_windows.ps1
```

## WSL Flutter Environment

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

无线调试端口会变化。以 `flutter devices` 当前显示为准，例如：

```bash
flutter run -d 192.168.2.181:42091
```

WSL 里如果旧无线设备还挂着，可以先断开旧地址再连新的：

```bash
adb disconnect 192.168.2.181:40273
adb connect 192.168.2.181:42091
adb devices
```

## Windows Python Environment

Windows 上安装 uv 和 Python：

```powershell
powershell -ExecutionPolicy Bypass -File .\install_uv_windows.ps1
```

然后安装服务端依赖：

```powershell
cd bluetooth_server
uv sync
```

## Start Server

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
uv run bt-server --mode both --channel 4
```

当前没有 `--ble-name` 参数。Windows WinRT GATT Server 主要通过固定 Service UUID 暴露服务，手机扫描时看到的设备名可能是电脑名，也可能是 `Unknown`。

## Client Modes

### RFCOMM Tab

RFCOMM 是 Bluetooth Classic 串口风格连接。使用前先在 Windows 设置里把手机和电脑系统蓝牙配对：

```text
Settings -> Bluetooth & devices -> Pair phone with this PC
```

App 操作：

1. 打开 `RFCOMM` tab。
2. 点击刷新已配对设备。
3. 选择 Windows 电脑。
4. 确认 `Channel` 和服务端一致，默认都是 `4`。
5. 点击连接。
6. 输入文本并发送。
7. 下方详情区查看最近发送、回包和错误。

RFCOMM 连接先尝试标准 SPP UUID：

```text
00001101-0000-1000-8000-00805F9B34FB
```

如果标准 UUID 连接失败，Android 原生层会按输入的 RFCOMM channel 做 fallback。channel 必须和 Windows 服务端 `--channel` 一致。

### BLE Bridge Tab

BLE Bridge 是给当前 Windows Python WinRT 后端用的固定协议。服务端固定暴露：

```text
Service UUID:        12345678-1234-5678-1234-56789abcdef0
Characteristic UUID: 12345678-1234-5678-1234-56789abcdef1
```

两个 UUID 的作用不同：

- `Service UUID` 用来标识“这是我们的 Bluetooth bridge 服务”。手机扫描到广告包后，如果广告里包含这个 Service UUID，就把它当成 Bridge 设备。
- `Characteristic UUID` 是连接成功并执行 service discovery 之后，用来定位真正收发消息的数据通道。Flutter 往这个 Characteristic 写入文本，Windows 收到后通过 notify 回 `Echo: ...`。

Bridge 模式查找规则：

- 扫描时不使用平台 service filter，先接收附近 BLE 广告，再在 App 内筛选。
- 默认只显示广告里包含固定 Service UUID 的 Bridge 设备。
- 如果同一个 Bridge 同时出现有名称设备和 `Unknown` 设备，隐藏 `Unknown` 那条，保留有名称的那条。
- 打开“其它设备”后，会额外显示有名称的非 Bridge BLE 设备，但它们不保证能按 Bridge 固定 Characteristic 收发消息。
- 列表按 Bridge 优先，再按 RSSI 信号强度由强到弱排序。

### BLE Explorer Tab

Explorer 是通用 BLE 浏览/试写模式，不要求对方使用我们的固定 UUID。

Explorer 查找规则：

- 默认显示有名称的 BLE 设备。
- 打开“无名设备”后才显示 `Unknown`。
- 设备列表按 RSSI 信号强度由强到弱排序。
- 连接后枚举全部 Service 和 Characteristic。
- 自动选择第一条可写 Characteristic，也可以手动点其它 Characteristic。
- 只有属性包含 `write` 或 `writeWithoutResponse` 的 Characteristic 才能写。

注意：可写只代表蓝牙属性允许写入，不代表对方设备能理解普通 UTF-8 文本。很多设备需要自己的二进制协议、配对、握手、校验或特定 write mode，所以 Explorer 连接别的设备时可能能连接但不能得到 echo。

## Run Flutter Client

在 WSL 里运行：

```bash
cd bluetooth_client
flutter pub get
flutter run -d 192.168.2.181:42091
```

## Verification

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
