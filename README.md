# Bluetooth

Flutter Android client + Go backend playground for BLE bridge testing.

## 目标

这个项目用于验证一条 BLE 桥接链路：

```text
Flutter Android App -> BLE GATT Server on Windows -> Go HTTP backend
```

第一阶段先做 Android 真机上的 Flutter BLE 调试客户端：扫描附近 BLE 设备、选择目标设备、连接/断开、发现 GATT 服务，并向可写 Characteristic 发送测试消息。

第二阶段在 Windows 上做 BLE GATT Server 桥接层：电脑暴露一个 BLE 服务，手机连接电脑后写入消息，Windows 桥接层收到写入事件，再转发给 Go 后端。

Go 后端只负责 HTTP 接收、记录和联调验证，不直接操作 BLE。

## 目录结构

```text
.
├── bluetooth_client/   # Flutter Android BLE client
├── bluetooth_server/   # Go HTTP backend
├── install_flutter_android_wsl.sh
└── install_flutter_go_windows.ps1
```

## 客户端

`bluetooth_client` 是 Android 真机 BLE 调试客户端，当前能力：

- 扫描附近 BLE 设备，默认隐藏未知设备，可手动显示未知设备。
- 按 RSSI 从强到弱排序，显示设备名、设备 ID、RSSI、信号强度和是否可连接。
- 选择设备后点击“连接蓝牙 / 断开蓝牙”。
- 连接成功后发现 GATT services，并自动选择第一个可写 Characteristic。
- 发送框会把输入内容按 UTF-8 写入 Characteristic。
- 详情区显示连接状态、MTU、service 数量、可写 UUID、最近发送内容和错误信息。

运行：

```bash
cd bluetooth_client
flutter pub get
flutter devices
flutter run
```

测试与构建：

```bash
cd bluetooth_client
flutter test
flutter analyze
flutter build apk --debug
```

## 后端

`bluetooth_server` 是给 Windows BLE 桥接层调用的 HTTP 服务。

接口：

- `GET /health`
- `POST /ble/messages`
- `GET /ble/messages`

启动：

```bash
cd bluetooth_server
go run .
```

默认监听 `:8080`，可以用 `ADDR` 改端口：

```bash
ADDR=:18080 go run .
```

发送一条测试消息：

```bash
curl -X POST http://localhost:8080/ble/messages \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"pc-ble","device_name":"Windows Bridge","payload":"hello"}'
```

查看消息：

```bash
curl http://localhost:8080/ble/messages
```

测试：

```bash
cd bluetooth_server
go test ./...
```

## Scripts

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install_flutter_go_windows.ps1
```

WSL / Ubuntu:

```bash
chmod +x ./install_flutter_android_wsl.sh
./install_flutter_android_wsl.sh
```

如果你想换安装目录，可以这样运行：

```bash
FLUTTER_DIR=$HOME/tools/flutter ANDROID_SDK_ROOT=$HOME/Android/Sdk ./install_flutter_android_wsl.sh
```

WSL 脚本默认安装 Flutter、Android SDK、Go 和必要系统依赖。默认启用国内镜像；如果要使用官方源：

```bash
NO_CHINA_MIRRORS=1 ./install_flutter_android_wsl.sh
```

## 完成安装后的下一步

1. 重新加载 shell 环境：

```bash
source ~/.bashrc
```

2. 接受 Android license：

```bash
flutter doctor --android-licenses
```

3. 手机上打开：

```text
开发者选项 -> 无线调试
```

4. WSL 里配对并连接真机：

```bash
adb pair 手机IP:配对端口
adb connect 手机IP:调试端口
adb devices
flutter devices
```
