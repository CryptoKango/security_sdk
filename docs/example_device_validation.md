# example 模拟器验收（2026-11-14）

## 范围与结果

运行的是根目录 `example/`，Flutter 3.44.9 / Dart 3.12.2。
集成测试通过实际页面按钮调用公开 SDK，再由测试专用主机 runner 操作系统 UI。
没有注入截图通知、伪造原生录屏回调、接入第三方指纹或访问物理设备。

| 项目 | Android | iOS |
| --- | --- | --- |
| 设备配置 | Medium Tablet，Android 15 / API 35，arm64 Google Play 镜像 | iPhone 17 Pro，iOS 26.5 Simulator |
| 原生规则版本 | local-v7 | local-v8 |
| Debug 集成入口重新构建、安装、运行 | 通过 | 通过 |
| capabilities、本地扫描、全部 14 项、单项扫描 | 通过 | 通过 |
| 模拟器识别 | detected / emulatorBuild | detected / emulatorBuild |
| Hook 无已知信号 | notDetected（不证明不存在 Hook） | notDetected（不证明不存在 Hook） |
| 缺少完整性/时间/位置输入 | 分别为明确 error | 分别为明确 error |
| 初始截图观察、读取、停止 | 通过；停止后 observationRequired | 通过；停止后 observationRequired |
| 系统/主机截图文件导出 | 成功；未触发截图阳性 | 成功；未触发截图阳性 |
| 录屏开始与停止 | **系统 Screen record / MediaProjection**：detected / screenCaptured → notDetected | simctl 视频导出成功；前中后 notDetected，**不属于系统录屏阳性验收** |
| 真实切后台/回前台 | HOME → example，包含 paused → resumed | 设置 → example，包含 paused → resumed |
| 回前台读取旧截图窗口 | error / observationInterrupted | error / observationInterrupted |
| 显式 start 替换中断窗口；stop/start 新开窗口 | 通过 | 通过 |
| 显式 dispose 后再查询 | disposed，未返回旧能力结果 | disposed，未返回旧能力结果 |

iOS 模拟器 Root 返回 unsupported / simulatorEnvironment；automation 返回 unsupportedPlatform。
iOS 本轮发现 tunnelInterface，仅说明系统存在隧道接口，不据此判定恶意、越狱或 VPN 提供方。
全量扫描包含依赖宿主输入的能力，缺配置时出现 error 是验收预期，不能把 14 项都有返回解释为 14 项都正常。

通过证据（第六次运行；JSON 不包含路径、地址、设备标识或 VM 令牌）：

- [Android 报告](validation_runs/2026-11-14/example_android_report.json) · [闭合观察值](validation_runs/2026-11-14/example_android_observations.json) · [界面](validation_runs/2026-11-14/example_android.png)
- [iOS 报告](validation_runs/2026-11-14/example_ios_report.json) · [闭合观察值](validation_runs/2026-11-14/example_ios_observations.json) · [界面](validation_runs/2026-11-14/example_ios.png)
- [失败轮次与原因](validation_runs/2026-11-14/example_failed_attempts.json)，失败没有被计入最终通过。

## 修复与回归

1. 补齐示例全部已实现公开方法、14 项单项/全量扫描、取消、超时、显式释放，以及宿主真实输入构造与注入示例。
2. 修正公开 `startScreenshotObservation()` 注释与示例说明：有效窗口重复 start 保留事件；
   中断后显式 start 可以替换窗口。仅回前台不会自动恢复。双端原生实现原本一致，不改变检测规则。
3. 初始 Android SystemUI ANR 抢占焦点时，SDK 正确保守返回 noActivity/观察不可用；恢复模拟器后复测，
   没有放宽前台判定。早期注入 SYSRQ 出现截图浮层干扰，自动化改用明确标识的外部导出，阳性留给真机。
4. Android 录屏改由真实系统 MediaProjection 开始/停止；授权 UI 会中断旧截图窗口，恢复后显式新开。
   SystemUI 录屏计时器使 uiautomator 无法 idle，停止操作复用同一轮观察到的 tile 位置，限定固定方向/布局。
5. 集成测试在 setUpAll 等待引擎初始语义回调，避免迟到的系统句柄被误当成测试泄漏；仍保留框架泄漏检查。
   不在异步 main 等待后注册测试，防止空执行。滚动后等待布局并验证按钮可命中，再点击。
6. runner 必须重新构建、drive 成功、全部主机步骤与 App 回执匹配、状态/生命周期断言完整才通过。
   空报告、步骤缺失/重复、未知状态、Android 外部导出冒充系统录屏、未恢复前台或未 dispose 均拒绝。
   构建错误不回显含测试令牌的命令。没有把导出成功当作系统截图通知成功。

本轮静态分析与仓库回归：76 项 Dart/Flutter（16 core、44 plugin、16 example），34 项 Python
（25 原窗口验收、9 新报告校验）。双平台真实运行各一个完整集成场景，包含上述多个阶段。
没有修改原生检测逻辑，本轮未重跑 Android JVM/Swift 策略测试，也未做最终 Release 真机验收。
复现命令与前置条件见 [example README](../example/README.md#模拟器自动化)。

## 单独待真机验收

| 验收项 | 操作与判定 |
| --- | --- |
| 两端真实截图事件 | 前台开始观察 → 物理按键截图 → 读取 screenshotObserved；重开后应清空；停止或后台时不继承旧事件。不要用 adb/simctl 截图替代。 |
| iOS 控制中心录屏、AirPlay/镜像 | 分别开始/停止并在宿主所属 Scene 读取捕获状态；区分镜像信号和录屏来源，测试前后台中断及多 Scene 归属。 |
| Android 厂商录屏与单应用共享 | API 35+ 全屏/仅本应用/其他应用共享；只有 SDK 所属 UID 可见于捕获时才判阳性，其他应用或不可确认不误报。 |
| 低版本与权限缺失 | Android 24–33 截图 unsupported、24–34 录屏 unsupported；Android 34/35 缺声明权限保留 error；iOS 13/16/17+ 真实设备路径分别验收。 |
| 截图/录屏与复杂生命周期 | 系统弹窗、旋转、分屏、PiP、多 Scene、多 engine 销毁/创建与真实捕获叠加；见既有窗口验收矩阵。 |
| App Integrity、时间、位置 | 使用受信任发布清单、认证接收时间、合法定位业务的真实样本验证匹配/不匹配、过期、未知来源与权限拒绝，不能用演示缺输入结果替代。 |
| Release Debugger、隐藏 Root/越狱/Hook、厂商分身 | 正常对照机 + 受控阳性设备；按既有专项矩阵验收。模拟器未检出不是对抗覆盖证明。 |

专项清单：[隐藏环境](hidden_environment_acceptance.md)、[iOS dyld](ios_dyld_snapshot.md)、
[真实窗口](real_window_validation.md)。第三方指纹仍未实现。

## 开发者设置扩展后的回归

上述 14 项报告属于扩展前的历史运行。当前示例包含 16 项，新增 developerMode / usbDebugging。
本轮 iOS 完整流程与 Android 新检测专用三状态用例通过；Android 完整录屏流程未通过，
未覆盖旧报告、未将历史通过当作新版本通过。见 [新检测验证记录](developer_settings.md#本轮验证2026-11-14)。
