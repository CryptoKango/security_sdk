# Native validation test app

Internal Android/iOS regression host for native detector integration, multiple
Flutter engines, real Scene creation/destruction, split-screen and PiP. For public
API usage and the runnable integration demo, use [example/](../../example/README.md).

Requires Flutter >=3.44.9 / Dart >=3.12.2. This test app resolves dependencies
independently of the portable SDK workspace. Its development-only
`pubspec_overrides.yaml` links the local SDK through `../../packages/`; its higher
minimum does not constrain SDK consumers. Application IDs remain unchanged so
existing explicit-device validation and the Android companion still address the
same test apps.

From this directory:

```sh
flutter pub get
flutter run
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/native_signals_test.dart \
  -d <simulator-id> --no-start-paused
```

The scan button explicitly calls implemented native detectors. Results depend on
platform and environment; unsupported or error does not mean the device is safe.
No backend, account or third-party fingerprint provider is required.

From the repository root, `CHECK_NATIVE_FIXTURE=1 sh tool/check.sh` also checks
this test app. For the actual OS-mode runners, companion setup and remaining
physical-device checks, see [real window validation](../../docs/real_window_validation.md).
These use `tool/run_window_validation.py` and an explicitly selected device.
Multi-Scene/PiP controls and background capabilities are Debug-only; signing team
and deployment credentials are not included.


## Android 截图回调对照

从仓库根目录运行 `python3 tool/run_capture_probe.py --device <physical-device> --flutter <flutter-path> --adb <adb-path> --output <new-output-dir>`。
需要 API 34+ 真机和 Flutter >=3.44.9。注册完成后提示 CAPTURE_READY，再用实体按键截图，
等待浮层消失，终端输入 `captured`；无法截图输入 `unable`，取消输入 `cancel`。
驱动对照原生回调与 SDK，记录有限的焦点/生命周期序列并验证停止和重开清理。
`passedWithInterruption` 只代表已确认截图和历史隔离通过，观察窗口仍中断。
未确认截图、没有原生回调、证据不完整不会判为通过。完整记录见本地 `docs/android_screenshot_history.md`。

无需人工截图的负对照入口为 `integration_test/capture_negative_test.dart`：真实 Dialog 造成焦点中断，
验证无截图时历史 false，以及同 engine 下两个 SDK 实例的独立重开、释放、停止。


## Android 真机窗口组合回归

先用本夹具的 Gradle/JDK 构建并安装独立伴随应用（无账号、无网络业务）：

```sh
(cd android && ./gradlew :window_companion:assembleDebug)
adb -s <physical-device> install -r build/window_companion/outputs/apk/debug/window_companion-debug.apk
```

仓库根目录运行：

```sh
python3 tool/run_physical_lifecycle.py --device <physical-device> \
  --flutter <flutter-path> --adb <adb-path> --output <new-output-dir>
```

要求 API 35+、Flutter >=3.44.9，开始时无录屏。驱动先自动旋转与双应用分屏；
阶段提示出现后才进行实体按键截图、启动无声音录屏、合上再展开、停止录屏。
每步动作完成且测试页恢复前台后输入 `confirmed`，不能执行输入 `cancel`。
截图不支持用 ADB 导出代替；录屏需要系统实际开始/停止，驱动核验 MediaProjection。
驱动不会擅自终止已有录屏；退出时 `recordingStillActive=true` 必须清理本轮录屏。
日志可能包含 Flutter 调试连接信息，只在本地保存；归档仅保留结构化 JSON，不提交原始日志。

两轮保持合上的验证使用 `--held-fold --closed-state <CLOSED-id>`。
CLOSED-id 必须先通过 `adb shell cmd device_state print-states` 确认，不能跨厂商硬编码。
每轮先完全合上并保持、确认 CLOSED，再展开回到测试页。合上阶段不要求前台。
禁止使用 `cmd device_state state <id>` 覆盖来冒充真实折叠。
此入口已补充自动校验，但真实合上/展开仍须可操作的折叠设备配合。

报告 `passed` 才表示全部证据齐全；`partialFoldUnverified`、`partialSplitUnavailable`
及 `blocked` 均不能计为全量通过。旋转必须有真实 orientation/configuration 变化，分屏必须
同时有两个应用的 multi-window 状态，折叠必须有真实状态变化及原生生命周期对照。
SDK 的 `observationInterrupted` 仍表示观察中断；保留的截图历史不代表观察连续有效。

## 单应用投影与 Activity / engine 回收

`integration_test/reclaim_test.dart` 在主 engine 外创建真实 FlutterActivity 和 engine，
每轮 `Activity.recreate()` 后保留 engine 并重新绑定；随后关闭 Activity，在 headless 状态查询，
最后 `FlutterEngine.destroy()`。共三轮，子 SDK 不主动 dispose，以检验原生 detach 清理。
这验证显式重建/销毁，不冒充系统低内存杀进程或 Dart/Java GC 验收。

```sh
DEMO_REPORT=<new-absolute-report.json> flutter drive \
  --driver=../../example/test_driver/device_driver.dart \
  --target=integration_test/reclaim_test.dart -d <physical-device> --no-start-paused
```

先按上节重建/安装伴随 APK，再从仓库根目录启动：

```sh
python3 tool/run_physical_lifecycle.py --projection-scope \
  --device <physical-device> --flutter <flutter-path> --adb <adb-path> \
  --output <new-output-dir>
```

驱动依次等待 `other_app`、`own_app`、`full_display`、`stopped`。
每次先结束上一轮测试投影（不得停止非本轮会话）：

```sh
adb -s <physical-device> shell am start \
  -n dev.securitysdk.window_companion/.ProjectionActivity --es mode stop
adb -s <physical-device> shell am start \
  -n dev.securitysdk.window_companion/.ProjectionActivity --es mode single
```

- `other_app`：在系统“共享一个应用”选择器选另一个测试包，例如公开示例 `Security SDK 示例`。
- `own_app`：停止上一轮，再用 `single` 打开选择器，选 `security_flutter_example`。
- `full_display`：停止上一轮，用 `--es mode full` 并确认“共享整个屏幕”。
- `stopped`：只执行 `stop`，确认 MediaProjection 已结束。

每个阶段回到 `dev.securitysdk.security_flutter_example/.MainActivity`，输入 `confirmed`。
驱动核对系统投影存在性及 SDK 返回；范围来自实际系统选择器操作确认，不能从“存在 MediaProjection”推断。
不同 UID 的另一测试包被录制时，当前 SDK 必须为阴性；失焦时仍是不可用，不得强制为阴性。
测试投影端没有音频权限、存储/上传逻辑；64×64 接收 Surface 的帧只关闭释放，不读取像素平面。
结束后检查 `recordingStillActive=false` 并卸载伴随 APK。
这是本地 MediaProjection 范围切换，不等于 Miracast/Chromecast/AirPlay 接收端实测。

## 内存回调、缓存 engine 与进程重启

`integration_test/cached_engine_test.dart` 通过官方 `FlutterEngineCache` 与
`CachedEngineIntentBuilder`，将同一个 engine 依次挂到三个新 Activity：
缓存 remove 后 engine 仍可查询，内存回调不产生截图；关闭宿主后必须重新开始观察。
缓存未命中明确返回夹具错误，不隐式创建 engine 或恢复旧结果；最后显式 destroy 再创建验证新 engine 无历史。

```sh
DEMO_REPORT=<new-absolute-report.json> flutter drive \
  --driver=../../example/test_driver/device_driver.dart \
  --target=integration_test/cached_engine_test.dart -d <physical-device> --no-start-paused
```

其中 `reclaimTrim` 是 **主动调用 onTrimMemory 的注入回归**，不是系统内存压力或 LMK 验收。
不填满手机内存，不修改“不要保留活动”等系统设置。

从仓库根目录可执行不依赖 Flutter driver 存活的受控进程重启回归：

```sh
python3 tool/run_process_restart.py --device <physical-device> \
  --flutter <flutter-path> --adb <adb-path> --output <new-output-dir>
```

要求 API 35+、开始时无投影。驱动构建并安装专用探针，每次启动先核对截图 observationRequired 和空缓存，
再建立截图观察、缓存 engine 并关闭子窗口。前两轮将测试应用切到后台，只对该包执行 `am kill`，
确认进程退出、重启后进程不同，再验证空缓存与新观察；不在两次重启间清数据或重装。
进程未退出时失败，不使用 force-stop 替代并伪装为成功。
初始准备与最终清理使用 force-stop，不计入测试终止事件。
报告不写入 PID、设备序列号或调试 token；日志只在本地保存，不归档原始调试日志。

结果 `passedControlledRestart` 仅代表受控后台进程终止/重启通过；
`actualLowMemoryKillVerified=false` 必须保留。退出原因来自系统最后记录，仅作辅助信息，
单独出现 lowMemory 不足以关联本轮被测试进程。本轮真实 LMK、iOS Jetsam 及物理折叠均未验收。

## Unified device report regression

`integration_test/device_report_test.dart` validates native metadata, all 16
findings, missing-input reasons, and repeated explicit reads on Android/iOS.
It is an API integration test, so it does not create a Widget-test semantics
baseline that can race the iOS accessibility startup handshake.

```sh
SECURITY_VALIDATION_REPORT=/tmp/device-report.json flutter drive \
  --driver=test_driver/window_validation.dart \
  --target=integration_test/device_report_test.dart -d <device-id>
```

Report fields include model and OS descriptors, never unique device identifiers.
A completed report alone is insufficient: the Flutter test process must also exit
successfully. Simulator validation does not replace physical-device acceptance.
