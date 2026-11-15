# 截图、录屏与多 engine 生命周期审查（local-v5 基线，local-v6 补充）

本轮仅修复采集窗口、资源归属和异步返回的可靠性，不扩大恶意行为判定。第三方指纹仍不实现。
`error/observationInterrupted` 表示连续观察条件已丢失，不能转换为截图阳性，也不能解释成没有截图。

## 已修复的问题

| 问题 | 最终行为 | 回归层次 |
| --- | --- | --- |
| 旧 start 超时清理新 start，或旧 stop 回执抹掉新监听的清理标记 | Dart 按操作修订号隔离；只有当前 start 的失败可清理当前窗口，旧 stop 回执不会覆盖后续 start | Dart 竞态回归 |
| 自定义异步 provider 在 stop/dispose/超时后才完成注册 | 完成或失败时检查最新意图，必要时有界补清理；新 start 仍需要观察时不误停 | Dart 延迟 provider |
| Activity 暂停仍保有焦点，焦点丢失/重绑后旧窗口复用 | 暂停标记、decor ViewTreeObserver 与 binding 焦点监听、Activity/Window 身份共同约束；中断不可逆，回前台必须显式 start | Android API 34/35 框架 |
| 注销失败留下可继续记事件的旧 callback | 先失效再注销；失败保留重试句柄，禁止直接替换并累积回调；旧 callback 检查 owner 与窗口身份 | Android 注销异常/迟到回调 |
| 录屏临时 callback 注销失败后每次扫描继续注册 | 每 engine 最多保留一个待清理句柄；下次查询先清理，失败返回 error，不把初始值当成功 | Android API 35 框架 |
| iOS 前台恢复后重用曾失活/隐藏的窗口 | 绑定弱 UIWindow 身份；监听所属 Scene 失活/后台/断开（无 Scene 才监听 App）、该 UIWindow 隐藏；先失效再释放 token | Swift 生命周期策略 |
| 混合 runtime/capture 扫描在异步计算后返回旧的 clean | Android epoch、iOS 临时生命周期 guard 与 owner 窗口身份共同检查；已成功采集的 capture 项遇到中断改为 error，原有错误原因保留 | Android 延迟 runtime；Swift guard 策略 |
| 一个实例或 engine 关闭影响另一个观察者 | 所有 owner/窗口/token/清理句柄为插件实例所有；停止或 detach 仅释放自身资源 | 原生相同 owner 双实例；示例真实双 engine |

此轮基线为 `local-v5`，当前为 `local-v6`（见 [多窗口后续审查](scene_window_lifecycle.md)）；桥接 schema 仍为 1，没有新增 detector/reason 或第三方依赖。

## 宿主接入顺序

1. 为每个 engine/业务观察方创建自己的 `SecuritySdk`；在可见、前台且有焦点的页面显式 start。
2. 同一实例的 start/stop 建议串行调用；有效窗口内重复 start 不清空已观察事件。
3. 页面离开时 stop；页面前台恢复后显式 start 建立新窗口。暂停、弹窗/系统界面导致的焦点丢失
   也可能使观察中断，这是覆盖缺口，不是攻击信号。不要把 error 统一转成 detected 或 notDetected。
4. 不再使用实例时 await dispose，并处理失败。engine detach 是兜底，不代替正常页面生命周期管理。
5. 合并了 Root/Hook 等异步扫描的结果，capture 项可能因期间切换而变成 observationInterrupted；
   在业务上下文有效时重新扫描。已经返回的快照不会随后自动更新。

每 engine 最多保留 64 个截图 owner（包括中断记录）。调用 stop/dispose 释放名额；不自动淘汰
其他 owner，也不自动恢复已中断窗口。普通 scan 不注册长期截图观察，混合扫描仅短期守护返回时效。

## 归属与误报边界

- **Android 截图**：API 34+、宿主显式权限、所绑定 Activity。事件说明该观察期收到系统回调，
  不证明用户有恶意，不覆盖 ADB、测试工具抓屏、外部摄像机或系统未通知的捕获方式。
- **Android 录屏**：API 35+ 是一次性查询，临时 callback 读取初始状态后释放。公开接口以注册进程
  UID 所属 Activity 是否出现在录屏中为范围，不能归属到某个 engine、Flutter view 或业务页面。
  headless engine 没有 Activity，即使同 UID 有前台页面也返回 error，不借用其他 engine 的页面。
- **iOS 截图**：系统截图通知属于进程范围，没有精确 Scene、engine 或像素归属。多个同时可见窗口
  都可能观察到同一通知；窗口隔离保证资源和生命周期独立，不保证事件能唯一归属。
- **iOS 录屏**：一次性读取当前绑定窗口的 Scene capture trait（支持时）或旧系统屏幕状态；后者
  范围更宽。镜像也可能命中。不实现持续录屏状态流，不读取截图内容，也不宣称能阻止截图。
- **多 Scene / engine**：local-v6 中 iOS Scene 事件只中断所属 Scene 的观察；App 级失活仅用于无 Scene 的旧式宿主。
  registrar.viewController 是 Flutter 的旧单 view 入口；无 controller 的 engine 不遍历全局窗口
  猜归属，尚不承诺一个 engine 同时承载多个 Flutter view 的精确支持。
- **Android 非标准宿主**：使用 Activity binding、公开 Application 生命周期回调和 decor 焦点通知。
  已验证当前 Flutter embedding 的 Activity 焦点路径不转发 binding listener，因此不能仅依赖该接口。
  若插件在已暂停 Activity 上才被绑定，且宿主保留焦点、又未产生后续暂停通知，无法追溯缺失事件；
  宿主仍须遵守前台 start 前提。不调用隐藏 LifecycleReference 或非公开生命周期 API。
- **失败清理**：原生注销异常保留有限重试；detach 时失效并清空插件状态，回调不强持有插件/窗口。
  这不能证明操作系统已成功注销。Dart 超时只结束等待，永不完成的自定义 provider 无法由门面强制
  取消；provider 必须实现自身取消/释放约定。SDK 不将 dispose 失败解释为清理成功。

## 自动化与尚未验收的范围

新增 7 项 Dart 生命周期竞态、17 次 Android API 34/35 框架回归、9 项 Swift 生命周期策略回归。
示例新增真实前台 engine + headless engine 用例，重复创建/销毁两轮；没有将“两 SDK 实例”冒充
“两 FlutterEngine”。同 Activity、相同 owner 的隔离由框架 fixture 单独覆盖。
Android 另用真实 Dialog 触发 OS 焦点切换，iOS 用 NotificationCenter 注入失活/截图通知验证真实订阅
接线及停止/重启；后者是合成事件，不是物理截图或真实后台切换验收。

Swift 策略在 macOS 执行，Android Robolectric 不是设备。模拟器集成也不能代替物理截图/录屏、
旧式 UIKit、多活 Scene、真实分屏、低版本设备与 OEM 生命周期差异。旋转/PiP 后续验证见 [scene_window_lifecycle.md](scene_window_lifecycle.md)。录屏权限撤销、系统服务
异常仅通过回归 fixture 覆盖。尚需上述真机矩阵；不要据此声称全设备检出或完全抗绕过。

运行记录与总量见 [roadmap.md](roadmap.md)；兼容矩阵见 [compatibility_review.md](compatibility_review.md)。

## 公开接口依据

- [Android WindowManager](https://developer.android.com/reference/android/view/WindowManager)：录屏回调初始状态、UID 范围及释放接口。
- [Android Activity 生命周期](https://developer.android.com/guide/components/activities/activity-lifecycle)：暂停、恢复与停止语义。
- [Android ViewTreeObserver 焦点监听](https://developer.android.com/reference/android/view/ViewTreeObserver.OnWindowFocusChangeListener)：直接监听窗口焦点变化。
- [Flutter ActivityPluginBinding](https://api.flutter.dev/javadoc/io/flutter/embedding/engine/plugins/activity/ActivityPluginBinding.html)：绑定 Activity 与焦点回调。
- [FlutterPluginRegistrar](https://api.flutter.dev/ios-embedder/protocol_flutter_plugin_registrar-p.html)：viewController 的单 view 兼容入口及 headless 情况。
- [FlutterPlugin](https://api.flutter.dev/ios-embedder/protocol_flutter_plugin-p.html)：engine detach 释放生命周期。
