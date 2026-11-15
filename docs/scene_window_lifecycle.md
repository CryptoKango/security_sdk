# 多 Scene、旋转、分屏与画中画审查（local-v6）

本轮只修复截图观察和录屏快照的上下文有效性、事件隔离与监听释放，不新增多开/攻击判据。
第三方指纹仍不实现。`observationInterrupted`、`observationRequired` 和 `noActivity` 是缺少有效
观察的错误状态，不能映射为风险阳性，也不能映射为没有截图/录屏。

## 问题与修复

| 审查项 | 已修复/明确的行为 | 误报控制 |
| --- | --- | --- |
| iOS 多 Scene 事件串扰 | 有 Scene 的观察只订阅所属 Scene 的失活、后台、断开和所属窗口隐藏；App 失活/后台仅用于无 Scene 的旧式 UIKit 宿主 | 另一个 Scene 的变化以及 App 级通知不再自动使当前活跃 Scene 的观察失效 |
| 同一 UIWindow 迁移到其他 Scene/屏幕 | 截图观察和混合扫描临时 guard 共同绑定弱 Window、Scene、Screen 身份；任一身份变化、丢失或有/无 Scene 转换均中断 | 不通过 Scene 数量、窗口大小、方向或屏幕编号判多开；不枚举其他应用/窗口 |
| Android decor 脱离后重新挂载 | 脱离时中断；重新挂载时移除旧/合并后的焦点监听并挂到当前 ViewTreeObserver；Activity detach 移除 attach/focus 两组监听 | 重挂载不自动恢复旧观察，不累积监听；仍需显式 start |
| Android 配置重建 | config detach/reattach 保留“观察中断”语义，旧回调不能记入新窗口 | 不把 Activity 重建当作 Hook、多开或截图事件 |
| Android PiP 与残留焦点 | 除暂停/焦点外，显式检查公开 `isInPictureInPictureMode`；PiP 中拒绝 start，截图窗口中断，录屏快照返回 noActivity | PiP 不是风险阳性；SDK 不改变宿主媒体播放或 PiP 行为 |
| 异步扫描返回时才发现中断 | 重新验证原 Activity/Window/decor 或 iOS Window/Scene/Screen；若旧 owner 仍是同一观察则将其永久失效 | 不仅把本次结果改为 error；也阻止恢复后旧窗口再次变成 clean，不影响随后建立的新窗口 |

规则版本为 `local-v6`，schema 仍为 1；没有新 detector/reason、SDK 依赖或宿主强制权限。
示例的 PiP 声明仅用于 Android Debug 测试，不写入插件 Manifest。

## 几何变化与有效观察

- **旋转/调整大小**：同一 Window/Scene/Screen（Android 为 Activity/Window/decor），且前台条件和
  监听连续有效时，窗口尺寸/方向变化不清零累计截图证据、不要求重新注册。真实 OS 若同时失焦、
  失活或重建，则中断是观察缺口；回前台显式 start，不能在旋转时无条件自动重开。
- **Android 分屏**：只要当前绑定窗口仍有焦点、未暂停且不在 PiP，允许观察。另一个窗口获焦，或
  旧系统把仍可见的 Activity 暂停时，按原有“前台有焦点”契约保守降级，不把“仍可见”推断成监听
  连续完整。API 29+ 多 resumed 也不表示多个窗口都有焦点。该限制不影响宿主正常多窗口业务。
- **iOS 分屏/Stage Manager**：使用所属 Scene 的 activationState 和实际窗口，不要求窗口是全屏，
  不要求全局 keyWindow，不因其他 Scene 事件中断；同一个 Scene 内窗口隐藏仍只影响该窗口。
- **iOS PiP**：AVKit 的系统 PiP 视频层不等于 Flutter registrar 所绑定的 UIWindow。SDK 没有通用
  iOS PiP 检测接口，也不接管 AVPictureInPictureController；主 Scene 失活时原观察中断。若主 Scene
  仍活跃，结果只适用于该窗口/系统 API 范围，不能据此说明 PiP 视频是否被捕获。
- **截图/录屏归属仍有限**：iOS 截图通知没有精确 Scene/像素归属；Android 录屏初始状态按 UID。
  生命周期隔离修复不会使这两个信号获得单 engine、单页面或 PiP 内容归属能力。

## 宿主实施顺序

1. 每个 engine/观察方单独持有 SDK；只在所绑定前台业务窗口上显式 start。
2. 页面离开时 stop；观察中断后，待本窗口前台条件恢复再显式 start。有效观察内重复 start 不清零。
3. 旋转、分屏缩放若没有中断，不需要手动 stop/start；若系统重建或返回 interruption，按新窗口
   重新建立观察。失败的显式 start 可能已清理旧记录，后续返回 observationRequired 仍是未知。
4. 进入 PiP 后不请求前台截图观察；媒体是否继续播放由宿主决定。退出后确认本 Activity/Scene
   已恢复前台再 start。不要仅依赖 Dart 层全局 appLifecycle 推断某个 Scene 的状态。
5. await dispose 并处理失败；遵守每 engine 64 个 owner 上限。清理失败、超时与 SDK 自定义
   provider 的边界继承 [capture_lifecycle.md](capture_lifecycle.md)，不保证强制取消 OS 工作。

## 回归层次与仍需验收的矩阵

- Swift 原生策略：独立 NotificationCenter 下验证双 Scene 隔离、同 Scene 双窗口隐藏隔离、旧式
  App 生命周期、Scene/Screen 身份迁移和弱引用丢失。对象替身只发往隔离中心，不能冒充真实多 Scene。
- Android 框架回归：同窗口方向/宽度变化保留证据、config 重建、分屏暂停、PiP 残留焦点、录屏
  前提拒绝、decor 重新挂载及异步返回时的 PiP 中断。Robolectric 不是设备。
- 模拟器集成：沿用双 FlutterEngine 和原生事件接线用例，新增 Scene 绑定窗口不受 App 失活通知
  影响、系统旋转，以及 Android 系统 PiP 进入/返回。具体执行结果和总量以 roadmap.md 为准。

仍需真机验证多活 UIWindowScene、iPad Split View/Stage Manager、Android 实际双应用分屏与
多显示器迁移、OEM 的旋转/PiP 动画时序、旧系统与物理截图/录屏正例。iOS 示例仍为单 Scene 配置；
没有将策略替身或 App 通知注入宣称为真实双 Scene 验收。一个 engine 多 Flutter view 仍受 registrar
单 view 入口限制。若宿主绕过系统生命周期并在两次检查之间迁出又迁回同一上下文，无法保证发现
所有瞬时缺口；SDK 不承诺持续跨窗口监控或完整抗绕过能力。

## 依据

- [Apple Scene 生命周期](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)：Scene 各自管理 UI 生命周期。
- [Apple UIScene](https://developer.apple.com/documentation/uikit/uiscene)：Scene 状态与生命周期通知。
- [Android 多窗口](https://developer.android.com/develop/ui/views/layout/support-multi-window-mode)：多 resumed、暂停与可见性的区别。
- [Android PiP](https://developer.android.com/develop/ui/views/picture-in-picture)：PiP 生命周期和宿主媒体职责。
- [Flutter UIScene 迁移](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)：App 与 Scene 职责拆分。


后续真实 OS 验证入口已补齐，见 [real_window_validation.md](real_window_validation.md)。
该入口要求实际多 Scene / 双应用状态或 AVKit 回调；具体已通过与仍失败项以 roadmap 最新运行记录
为准。本节前述策略/旋转测试不代表全部真实窗口矩阵已通过。
