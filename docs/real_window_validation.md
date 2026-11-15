# 真实多 Scene、双应用分屏与 iOS PiP 验证

本轮补的是验证设施与可复现方案，检测规则仍为 `local-v6`。不增加第三方指纹、不将多窗口/PiP
视为攻击，也不把缺权限、生命周期中断、平台不支持或没有进入目标模式记为“未检测到”。

## 可自动化入口

所有设备必须显式指定。运行器不启动/选择真机，不安装 companion、不修改系统设置，不发布包。
iOS 默认构建模拟器应用；物理测试机需额外传 `--ios-device`，并预先配置签名。
先准备 Flutter 依赖与已启动的模拟器/已授权测试机，再从仓库根目录运行：

```sh
python3 tool/run_window_validation.py --scenario ios_scenes \
  --device <iPad-device-id> --flutter <absolute-flutter-path> --report /tmp/scenes-new.json
python3 tool/run_window_validation.py --scenario ios_pip \
  --device <iOS-device-id> --flutter <absolute-flutter-path> --report /tmp/pip-new.json
```

Android 分屏使用真正的第二个 APK，应用 ID 为 `dev.securitysdk.window_companion`。它无网络、存储、
包枚举或设备身份权限，仅显示测试页面，通过请求携带的 ResultReceiver 返回模式/焦点等布尔状态。
编译、安装到明确指定的测试设备后执行：

```sh
cd test_apps/native_validation/android
./gradlew :window_companion:assembleDebug
cd ../../..
adb -s <test-device-id> install -r test_apps/native_validation/build/window_companion/outputs/apk/debug/window_companion-debug.apk
python3 tool/run_window_validation.py --scenario android_split \
  --device <test-device-id> --flutter <absolute-flutter-path> --report /tmp/split-new.json
# 验收后仅卸载测试 companion；不要卸载宿主或其他应用。
adb -s <test-device-id> uninstall dev.securitysdk.window_companion
```

自动启动相邻应用使用 API 32+ 的公开 FLAG_ACTIVITY_LAUNCH_ADJACENT。旧 Android 或厂商系统不按
请求进入分屏时，转为下述人工矩阵，不调用隐藏 windowing API、不把自由窗口/普通前后台切换冒充
双应用分屏。仅靠 isInMultiWindowMode 不能在所有 OEM 上唯一识别分屏与自由窗口，真机报告还须
记录系统分屏布局的可视证据；自动报告保留双方模式与焦点，使用已知平板分屏环境执行。

companion 必须成功回报；缺少回报按夹具/IPC 失败处理，不能推断系统不支持分屏。
跨 APK 的 ResultReceiver 会先还原为 framework 类型，避免对端加载本应用匿名子类。

退出码：`0=passed`，`3=blocked`（环境前提未满足），`1=failed`（断言/传输/报告校验失败）。
Flutter 的“All tests passed”不代表目标系统模式已经验证；必须以运行器退出码和 JSON 为准。
运行器先独立构建并检查退出码，再以 `--use-application-binary` 运行该产物；构建失败不得回退到
已安装的旧应用。通过报告必须含 `buildValidated=true`。Flutter drive 的失败重试不能替代此门禁。
Scene 场景固定执行三轮；任一轮未完成、资源仍被持有或最终 registry 非空，都不得通过。
已有 JSON/log 不会复用或覆盖；每次选择新路径。没有报告、清理失败或缺少证据都不能通过。

## 自动化实际做什么

| 场景 | 系统操作与证据 | SDK 断言 | 尚未代表的覆盖 |
| --- | --- | --- | --- |
| `ios_scenes` | UIKit 实际请求第二 UISceneSession；独立 FlutterEngine/FlutterViewController/SDK；验证 distinctScenes、子引擎 ready 与采集；连续三轮实际激活双方；激活待关闭 Scene 后请求销毁，确认系统会话移除、断开回调及 engine/plugin/controller 弱引用归零 | 主 Scene 真正失活后 error；第二 Scene 可独立 start/scan；销毁另一 Scene 时若本 Scene 无中断则保持有效，有中断则 error | 两个 connected Scene 不等于同时 foregroundActive；iPad 双活、Stage Manager 布局和物理截图仍需单独验收 |
| `android_split` | 启动单独 companion APK；必须得到双方 multiWindow 与 companion 焦点证据；关闭 companion 并确认主应用恢复全屏、有焦点且 resumed | 失焦旧观察 error/interrupted、start 拒绝；恢复后显式 start 才建立有效窗口 | 不等于 OEM 全覆盖、真实截图检出率；需人工确认布局确为分屏 |
| `ios_pip` | AVAssetWriter 在临时目录生成离线测试视频；AVQueuePlayer/AVPlayerLayer + AVPictureInPictureController；要求 possible、didStart 回调和 active，再等待 didStop 与 inactive | 依主 Scene 的实际 activation 与中断计数断言 notDetected/error；PiP 本身不能制造截图阳性；释放播放器/临时文件/音频会话 | 不证明 PiP 视频内容是否被截图/录屏；不自动验证 Home 后台、锁屏、外部媒体或生产 AVKit 接入 |

iOS 的多 Scene 声明和 background audio 仅在 `Info-Debug.plist`，播放器/控制通道仅在 DEBUG。
每个主 engine 的 fixture 由其 registrar 持有，避免 AppDelegate 单一字段覆盖其他 engine。
Scene registry 只保存本次显式请求的有限测试会话，不属于 SDK，不收集其他应用或设备身份。
自动化不向 UIKit 全局通知发送伪造 Scene 对象；对象替身只用于独立 NotificationCenter 策略测试。

## 真机/系统验收步骤与断言

每次记录 OS/设备类别、宿主构建模式、是否采用 Scene、实际权限与每步状态/reason；不要记录设备
标识、截图内容、用户媒体或 SDK 原始证据。测试素材必须无敏感信息。以下均需显式开启观察。

| 编号 | 操作顺序 | 必须检查的结果 |
| --- | --- | --- |
| M1 双活 Scene | iPad 开两个应用窗口并排；两边分别 start；切换 A/B 焦点；保持两 Scene 活跃时关闭 B | 记录两边独立 activationState；A 无自身中断时不能因 B 的通知或清理失效；若 A 实际失活则必须 error |
| M2 Scene 迁移/回收 | A 建观察；拖动窗口/切换显示器；关闭 B；恢复 A；重复 10 轮 | 纯尺寸变化不清零证据；Window/Scene/Screen 身份变化或 disconnect 必须中断；重启不能继承旧阳性，监听不累积 |
| S1 双应用分屏 | 系统分屏入口打开宿主+companion；拍布局证据；切换焦点两轮；拖分隔线；关闭 companion | 两应用均在分屏；仅变尺寸不制造阳性；失焦/暂停返回 error；恢复后显式 start；检查已有截图标记不被尺寸变化清空 |
| S2 低版本/OEM | Android 24–28 的可见但 paused 分屏；API 29+ 多 resumed；厂商分屏、旋转、后台再恢复 | 可见不等于满足前台契约；不得把 paused/无焦点的未知转 clean；厂商不支持模式记 blocked，不记通过 |
| P1 iOS PiP 内联 | 用 fixture 或宿主实际 AVKit 播放器启动 PiP；确认系统浮窗；主 Scene 留前台；停止 PiP | 以 didStart/didStop 和 active 为证，不以 start 请求成功为证；SDK 只评价绑定的主窗口，PiP 不算风险阳性 |
| P2 PiP 后台/锁屏 | PiP active 时按 Home/切其他 App；读宿主原生审计状态；恢复主 Scene；显式重开；再锁屏/解锁 | 主 Scene 失活后旧观察永久 error；恢复不能自动 clean；不要依赖后台 Flutter driver 连接存活作为安全结论 |
| P3 拒绝与失败 | 不支持设备、possible=false、系统拒绝启动、媒体失败、取消/退出播放器 | 启动条件未满足/OS 拒绝是 blocked；素材生成或测试实现出错是 failed；没有 didStart 不能宣称验证成功 |
| C1 真实捕获正例 | 在合法测试窗口用系统截图/录屏操作；与外部摄像机/ADB 抓屏区别记录 | 只确认公开 API 能发出的事件；iOS 截图无精确 Scene 归属、Android 录屏按 UID，不宣称能确定 PiP 内容归属 |

iOS 后台/锁屏涉及 VM 服务停用，完整路径应由 XCTest/XCUITest/人工驱动前后台并在恢复后读取审计
记录；不能靠注入 App 后台通知维持 Flutter driver 来冒充真实系统行为。本轮脚本覆盖前台 PiP
启停，P2 是明确的后续真机项目。并行开两个窗口后应核验真实 active 状态，不以窗口可见代替。

## 回归与发行隔离

- `sh tool/check.sh`：Dart/Flutter 格式、分析、既有测试及运行器 Python 回归。
- `python3 -m unittest discover -s tool -p test_window_validation.py`：报告拒绝伪通过、缺证据、错场景、布尔冒充计数等。
- `RunnerTests` 可在 `test_apps/native_validation/ios` 执行：
  `xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=iOS Simulator,id=<test-id>' -only-testing:RunnerTests FLUTTER_TARGET=lib/main.dart CODE_SIGNING_ALLOWED=NO test`。
- `RunnerTests`：替换失效的模板平台版本测试，验证 headless/未开始观察/空 owner/幂等 stop 的原生桥接语义。
- 已有 Swift 策略、Android 框架与 `native_signals_test.dart` 仍保留；它们不替代上述真实 OS 场景。
- Release 需核验 Info.plist 不含测试多 Scene/background audio 改动、二进制不含验证控制通道。

执行结果、环境和 blocked/failed 原因记录在 [roadmap.md](roadmap.md)。真实环境尚未达到的维度
继续作为缺口，不以“有测试代码”或“编译成功”替代验收。第三方指纹、自动上报和业务拦截仍未实现。

## 公开接口依据

- [Apple UISceneSession](https://developer.apple.com/documentation/uikit/uiscenesession)：系统创建/激活 Scene 会话。
- [Apple Scene 销毁](https://developer.apple.com/documentation/uikit/uiapplication/requestscenesessiondestruction(_:options:errorhandler:))：请求销毁不应直接当作断开完成。
- [Apple AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller)：supported、possible、active 与 delegate 生命周期。
- [Android 多窗口](https://developer.android.com/develop/ui/views/layout/support-multi-window-mode)：相邻启动与版本差异。


## Scene 关闭问题的定位与修复（2026-11-13）

原失败不是 SDK 漏接了已发生的关闭。在 iOS 26.5 iPad 模拟器上，后台目标的销毁请求被
SpringBoard 的窗口校验器否决，系统日志明确记录 `Vetoed by request validator`。命名配置修复后、
等待连续六次状态稳定后仍可复现；errorHandler 未回报错误不能证明系统完成了操作。这是该环境的
实测边界，不推广为所有 iOS 都禁止后台关闭，也不使用私有 API 绕过系统校验。

验证宿主现在明确分两步：先用公开激活 API 激活待关闭 Scene，确认其 foregroundActive，再请求
销毁。直接对非活跃测试 Scene 调用关闭会返回 `fixture_scene_inactive`，请求计数不增加。
成功必须同时满足真实 `sceneDidDisconnect`、AppDelegate 的会话丢弃通知、`openSessions` 和
`connectedScenes` 中不存在原会话；不会通过手动调用 disconnect、伪造通知或手动置位来宣称关闭。
该激活流程只在 Debug 验证宿主中，安全 SDK 不自动切换窗口或修改宿主生命周期。

另修复两项夹具接入问题：配置名原先未声明在 plist，且运行时再次赋值 delegate/storyboard 会在
本次 UIKit 中清空配置名。现由 Debug plist 提供完整命名配置，AppDelegate 直接返回，回归检查
实际会话保留该名称。第二 Scene 继承 FlutterSceneDelegate 并转发生命周期；临时测试 Scene 不
参与状态恢复，避免恢复旧 token。可选 didDiscardSceneSessions 只记录已观察到的系统回调，不调用
当前 FlutterAppDelegate 没有实现的父类方法。配置与生命周期接入依据：
[Apple UISceneConfiguration](https://developer.apple.com/documentation/uikit/uisceneconfiguration/init(name:sessionrole:))、
[Flutter Scene 接入](https://docs.flutter.dev/add-to-app/ios/add-flutter-screen)。

每轮还要求：

- 子 Scene 开始观察前是 `error/observationRequired`，显式 start 后才可正常采集。
- 销毁时子 SDK 保持已开始观察，依靠 engine detach 清理；不先手动 dispose 子 SDK 掩盖问题。
- delegate 断开回调与宿主清理各一次；engine isolate 已销毁，engine/plugin/controller/window
  的弱引用全部归零。单纯调用 destroyContext 或把强引用设为 nil 不足以通过。
- 重复 close 幂等、已关闭子 Scene 的命令被拒绝；主 Scene 如有自身生命周期中断，旧观察保持中断，显式 start 后才恢复；双活且自身未中断时不能强制报错。
- 三轮会话和 engine 独立，registry 每轮不累积，结束后显式释放终态记录并确认数量为零。

诊断字段 `disconnectedNotification` 不是通过依据：宿主在 delegate 回调清理观察者时，UIKit 的
全局通知可能尚未发布。真实关闭凭独立的 delegate 回调、会话列表和对象释放证据判定。
setup 或清理抛错会显式把报告改为 failed；不能依赖 Flutter driver 对 setup 失败的退出码判断。

已通过的三轮证据见 [ios_scene_cycles.json](validation_runs/2026-11-13/ios_scene_cycles.json)。
原后台直接关闭失败的 [ios_scenes.json](validation_runs/2026-11-13/ios_scenes.json) 保留，不能改写为
通过。本轮没有证明双 Scene 同时 foregroundActive，也没有证明后台直接销毁、旧式 UIKit、真机
或 Stage Manager 的行为。第三方指纹仍不实现，生产检测规则仍是 `local-v6`。

## 测试宿主目录整理（2026-11-14）

原生验收宿主集中在 `test_apps/native_validation/`；根 `example/` 保留为公开 API 接入演示。
运行器、companion 命令与 XCTest 路径均使用新目录。宿主继续独立解析依赖，
`../../packages/` 覆盖路径、应用 ID、测试资源和原生测试代码保持不变。
迁移后清理并重新生成 Flutter/Xcode 缓存，避免旧绝对路径或旧构建产物掩盖问题。

新目录实测：全仓 76 项 Dart/Flutter、39 项 Python 回归（包含三场景运行器路径检查）、
105 项 Android JVM 回归通过；Android 双应用分屏、iOS 三轮真实 Scene 创建/关闭及
engine 回收、iOS PiP 真实启停均通过。所有运行器报告均有 `buildValidated=true`。
验证使用 Flutter 3.44.9、Android API 35 平板模拟器和 iOS 26.5 iPad 模拟器。
[迁移验证摘要与场景报告](validation_runs/2026-11-14/native_validation_move.json)。
本轮未执行真机测试，原有独立真机验收边界不变；未修改 SDK 检测规则或加入第三方指纹。
