# Bluetooth

Flutter Android client + Windows Python Bluetooth Classic RFCOMM server.

## 目标

这个项目用于验证一条最小蓝牙通讯链路：

```text
Flutter Android App -> Bluetooth Classic RFCOMM -> Windows Python Server
```

手机端不再做 BLE GATT 扫描。现在的流程是先在 Windows 设置里把手机和电脑完成蓝牙配对，然后 Flutter App 读取 Android 系统里的已配对设备，选择 Windows 电脑，建立 RFCOMM 连接并发送文本。Windows Python 服务端收到文本后打印，并返回 `Echo: ...`。

## 目录结构

```text
.
├── bluetooth_client/        # Flutter Android RFCOMM client
├── bluetooth_server/        # Windows Python RFCOMM server, managed by uv
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

Windows 上只需要安装 uv 和 Python：

```powershell
powershell -ExecutionPolicy Bypass -File .\install_uv_windows.ps1
```

然后在 Windows 设置里完成：

```text
Settings -> Bluetooth & devices -> Pair phone with this PC
```

## 启动 RFCOMM 服务端

在 Windows PowerShell 里运行：

```powershell
cd bluetooth_server
uv run bt-server
```

默认使用 RFCOMM channel 1。如果被占用：

```powershell
uv run bt-server --channel 2
```

注意：这个服务必须跑在 Windows Python 上，不要跑在 WSL 里。WSL 不能直接拿到 Windows 蓝牙控制器。

## 启动 Flutter 客户端

在 WSL 里运行：

```bash
cd bluetooth_client
flutter pub get
flutter run -d 192.168.2.181:40273
```

App 内操作：

1. 点击“刷新已配对设备”。
2. 选择 Windows 电脑。
3. 点击“连接”。
4. 输入文本并点击发送。
5. 下方详情区查看最近发送和 Windows 服务端回包。

## 测试

Flutter：

```bash
cd bluetooth_client
flutter test
flutter analyze
flutter build apk --debug
```

Python 服务端：

```powershell
cd bluetooth_server
uv run python -m unittest discover tests
```
