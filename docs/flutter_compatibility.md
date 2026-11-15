# Flutter 版本兼容

目标从 Flutter **3.38.10 / Dart 3.10.9** 起，持续适配最新稳定版。Flutter 不设上限，
Dart 保留 `<4.0.0` 主版本边界。声明范围不等于未来所有版本已经验证；每次 stable 更新由 CI 重新验收。
当前官方 stable 分支与 3.50.0 标签均指向 `ab2912035e160d9cad6306df307576da6128ebdb`（2026-11-14 查询）。
[官方发布说明](https://docs.flutter.dev/release/release-notes)、[官方标签](https://github.com/flutter/flutter/tree/3.50.0)。

## 兼容实现

- SDK 与根 `example/` 的最低 Dart 约束降到 3.10.9；`security_flutter` 最低 Flutter 为 3.38.10。
  开发依赖 test 允许最低 Flutter 固定的 test_api 版本，不强制升级到新 Flutter 的测试依赖。
- 插件不再固定 AGP/Kotlin 版本，继承宿主声明；AGP 8 才显式应用 Kotlin Android 插件，
  AGP 9 由 Flutter 宿主的迁移桥接负责应用 Kotlin。按 [Flutter 官方跨版本插件迁移方案](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors#support-flutter-versions-earlier-than-344) 配置编译目标。
  插件自身 Android minSdk 24 / compileSdk 36、iOS deployment target 13 不变。
  **最终 App 的系统下限取插件、宿主与 Flutter 引擎要求中的较高值。Flutter 3.50 会将 iOS App
  的最低部署版本迁移到 15.0**，不能将支持 Flutter 3.50 理解为仍可在 iOS 13/14 运行。
  [官方 3.50 部署迁移实现](https://github.com/flutter/flutter/blob/3.50.0/packages/flutter_tools/lib/src/ios/migrations/ios_deployment_target_migration.dart)。
- 根 example 保留 `FlutterSceneDelegate` / implicit engine 注册，3.38.10 已包含这些接口。
  使用 CocoaPods 并在 example pubspec 关闭 SPM 自动迁移，避免不同工具链生成的临时 SPM 包互相污染。
  SDK SPM 支持保留；专用原生夹具保持原有 SPM/Scene 实现。
- Flutter 3.50 将 `flutter/material.dart` 标为弃用但仍提供兼容导出；为支持 3.38，
  仅对示例两处导入使用带说明的定点 lint 忽略，不关闭整个工程的弃用检查。
- `test_apps/native_validation` 是 Flutter 3.44.9+ 的高级 Scene/PiP 验收夹具，独立解析依赖，
  不再拉高公共 SDK 和通用 example 的门槛；其 path overrides 仅用于本仓库开发。
- 不改变 Root/Hook、截图录屏等检测判定，不加入第三方指纹。

## 本地实测结果（2026-11-14）

| Flutter / Dart | 分析、76 项测试 | Android Debug / iOS Simulator 构建 | iOS App 最低版本 |
| --- | --- | --- | --- |
| 3.38.10 / 3.10.9 | 通过 | 通过 / 通过 | 13.0 |
| 3.44.9 / 3.12.2 | 通过 | 通过 / 通过 | 13.0 |
| 3.50.0 / 3.14.0 | 通过 | 通过 / 通过 | 15.0 |

[结构化构建矩阵](validation_runs/2026-11-14/flutter_compatibility_matrix.json)。
最终配置另通过 105 项 Android JVM 回归（0 失败、0 跳过），以及 `sh tool/check.sh`
的 76 项 Dart/Flutter、38 项 Python 回归；Flutter 3.44.9 下开启 `CHECK_NATIVE_FIXTURE=1`
后，独立 Scene/PiP 夹具依赖解析、格式和分析也通过，本轮未重跑该夹具的真实窗口模式用例。

在 iOS 26.5 模拟器分别运行 3.38.10 与 3.50.0 构建的根 example，扫描、缺失输入错误、
真实前后台切换、监听中断/显式重启及释放均通过：
[最低版运行报告](validation_runs/2026-11-14/flutter_338_ios_runtime_report.json)、
[最新版运行报告](validation_runs/2026-11-14/flutter_350_ios_runtime_report.json)。
截图和 simctl 视频导出只是流程验证，**不等于物理截图通知或真实系统录屏阳性**。
本轮未运行 Android 设备集成，也不据构建成功宣称隐藏环境检出率或所有中间 Flutter 版本均已实测。

需要单独真机验收：iOS 截图通知/系统录屏阳性、旧系统可运行性、真实多 Scene/PiP，
以及隐藏 Root/越狱/Hook 和厂商分身；沿用 [真机清单](example_device_validation.md#单独待真机验收)
与 [隐藏环境清单](hidden_environment_acceptance.md)。未来 stable 升级仍需运行矩阵。

## Android 工具链不能固定成同一套

不同 Flutter 版本要求不同 Gradle/AGP/Kotlin。按所选 SDK 的官方模板读取默认值，
不通过 `--android-skip-build-dependency-validation` 跳过检查。

| Flutter | Gradle | AGP | Kotlin |
| --- | --- | --- | --- |
| 3.38.10 | 8.14 | 8.11.1 | 2.2.20 |
| 3.44.9 | 9.1.0 | 9.0.1 | 2.3.20 |
| 3.50.0 | 9.5.0 | 9.3.1 | 2.4.20 |

这些是本轮使用的示例构建组合，不是 SDK 强制所有消费者使用的唯一版本。
脚本读取官方模板版本，同时按迁移指引在 AGP 9 去掉插件/app 显式 KGP 声明，
保留 Flutter 当前迁移桥接要求的 builtInKotlin=false / newDsl=false。AGP 8 恢复显式 KGP
并移除 AGP 9 标志。**默认矩阵使用 Flutter 的 AGP 9 兼容桥接，不将纯内置 Kotlin 作为全版本默认。**
额外强制 builtInKotlin=true 的 3.44.9 验证失败：Flutter 的 detectApplyingKotlinGradlePlugin
仍自动应用 KGP，与内置 Kotlin 冲突（integration_test 的 Android library 配置阶段）。
3.50.0 的额外纯内置 Kotlin 构建已通过，但为覆盖整个版本范围，默认 example 仍保留桥接方式。
[额外模式验证结果](validation_runs/2026-11-14/flutter_builtin_kotlin_probe.json)。
不改 Flutter SDK 或跳过检查；未来迁移由 stable 矩阵重新验收。
脚本若无法识别未来模板格式，会失败并要求审查，不猜测版本或部分改写工程。

运行/切换 example 的 Flutter SDK 时，在仓库根目录执行：

```sh
python3 tool/configure_example_android.py --flutter /absolute/path/to/flutter
/absolute/path/to/flutter pub get
cd example
/absolute/path/to/flutter run -d <device-id>
```

通用 example 要求安装 JDK 17，并通过 `example/android/gradle/gradle-daemon-jvm.properties`
的 `toolchainVersion=17` 选择 Gradle Daemon。此前普通运行会继承 Android Studio JDK 25，
在 Gradle 8.14 上复现 `What went wrong: 25.0.2`；矩阵的显式 JDK 覆盖曾掩盖该缺口。
现在默认 runner 和 CI 使用项目本身的 JVM 配置，且不修改全局 Flutter/Java 设置。
[Gradle Java 兼容表](https://docs.gradle.org/current/userguide/compatibility.html)、
[Daemon JVM 优先级](https://docs.gradle.org/current/userguide/gradle_daemon.html#sec:daemon_jvm_criteria)。
如需额外测试指定 JDK，runner 仍接受 `--jdk-home`：只在隔离副本中移除优先级更高的
Daemon criteria，然后写入 org.gradle.java.home；原仓库保持 JDK 17 默认。

## 可重复验证

```sh
python3 tool/check_flutter_compatibility.py \
  --flutter /path/to/flutter_3.38.10/bin/flutter \
  --flutter /path/to/flutter_3.44.9/bin/flutter \
  --flutter /path/to/flutter_3.50.0/bin/flutter \
  --native android ios \
  --output /tmp/security-flutter-new-run
```

输出目录必须是新目录。每个 SDK 使用独立仓库副本和生成状态，分别执行依赖解析、core/plugin/example
分析、当前 Dart/Flutter 回归测试，以及 arm64 Android Debug APK / iOS Simulator Debug 构建。
`--native` 不传时仅验证 Dart/Flutter；运行 iOS 构建需要 macOS/Xcode/CocoaPods。
日志留在本机；报告只记录版本、阶段结果与工具链，不发布绝对路径。

`.github/workflows/flutter-compatibility.yml` 包含固定版本和滚动 stable，分别在 Linux/macOS
构建 Android/iOS。尚未推送或执行远端 CI，本地结果与 CI 配置分别说明。
默认 `sh tool/check.sh` 面向最低版本 workspace；在 Flutter 3.44.9+ 上使用
`CHECK_NATIVE_FIXTURE=1 sh tool/check.sh` 额外检查独立原生夹具。

系统版本能力边界仍见 [检测矩阵](detection_coverage.md) 和 [真机待验收](example_device_validation.md#单独待真机验收)。

## 普通运行的 JDK 选择回归（2026-11-14）

已在本机原样复现 Java 25.0.2 / Gradle 8.14 的失败，增加项目级 Daemon JVM 17 配置后，
同一 Flutter 3.38.10 直接构建 Debug APK 成功，无需设置 JAVA_HOME 或全局 flutter config。
另以 JBR 25 显式启动 Gradle，构建进程实际输出 Java 17.0.20.1。

不传 `--jdk-home` 的 3.38.10 / 3.44.9 / 3.50.0 隔离矩阵全部通过分析、每版 76 项测试与
Android Debug 构建。根仓库最低版检查通过 76 项 Dart/Flutter 和 41 项 Python 回归，
包括显式 JDK 覆盖优先级、无效 JDK 保持原配置的测试。此轮没有重新执行设备运行回归。
[实际验证记录](validation_runs/2026-11-14/gradle_jdk_selection.json)。
