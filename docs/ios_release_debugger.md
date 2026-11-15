# iOS Release Debugger 检测

## 结论与兼容性取舍

本库增加了 Release **显式启用**的尽力检测：读取本进程 `sysctl(KERN_PROC_PID)` 返回的 `P_TRACED`
标志。上一版的 `#if DEBUG` 是保守工程选择，不表示该系统调用在 Release 编译后就无法运行。
当前探针在所有构建中编译，宿主按请求选择是否允许在 Release 使用。

Apple 的 [QA1361](https://developer.apple.com/library/archive/qa/qa1361/_index.html) 给出了这条检测路径，
同时建议因 `kinfo_proc` 结构不稳定而仅在 Debug 构建使用。该文档已归档；当前 SDK 仍提供相关声明，
不等于 Apple 保证它未来兼容或保证 App Store 审核结果。因此默认仍是 `debugBuildOnly`；
Release 使用需要宿主显式选择 `allowReleaseProcessTrace`，并对实际支持的 iOS/分发构建进行验证。

`detected/debuggerAttached` 只表示读取时 OS 报告本进程被追踪；不是 debugger 身份识别、远程证明
或不可绕过的反调试。调试器暂停进程期间，探针本身也不能执行，需进程恢复运行后才能观察。
`notDetected` 不排除 Dart VM 服务、未设置该标志的工具、Hook 后的假数据或后续才发生的附加。

## 接入

```dart
final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-debugger-check',
  detectorIds: [SecurityDetectors.debugger],
  iosDebuggerMode: IosDebuggerMode.allowReleaseProcessTrace,
  timeout: const Duration(seconds: 5),
));
final finding = result.findings.single;
// 根据 status + reason 处理；error/unsupported 不能折算为正常。
await sdk.dispose();
```

配置属于当前 ScanRequest，不存为全局开关，不影响其他 SDK 实例，也不自动沿用到下一次请求。
没有请求 `debugger` 时不向原生传递此选项。Android 忽略 iOS 专用模式，沿用既有实现。
省略选项等同 `IosDebuggerMode.debugBuildOnly`：原生 Debug 可以检测，原生 Release 不执行查询。
Debug/Release 由插件 Swift 编译条件 `DEBUG` 决定，不能仅从宿主的 Dart 编译模式推测。

```dart
final capability = (await sdk.capabilities())
    .singleWhere((item) => item.id == SecurityDetectors.debugger);
// iOS 实现存在时 supported=true。
// 原生 Release 时 requiresExplicitOptIn=true，提示需要请求级显式选项。
```

`requiresExplicitOptIn` 是新增的可选能力字段；旧插件不返回时解析为 false。
能力存在不保证当前 OS 查询成功，也不意味着 Release 默认已启用。

## 返回值与失败处理

| 条件 | status | reason |
| --- | --- | --- |
| Release 未显式启用 | unsupported | releaseDebuggerOptInRequired |
| 成功读取，P_TRACED=1 | detected | debuggerAttached |
| 成功读取，P_TRACED=0 | notDetected | noKnownSignal |
| OS 权限拒绝 | error | probeAccessRestricted |
| 返回结构长度或本进程 PID 不一致 | error | processInfoMismatch |
| 其他 sysctl 失败 | error | nativeFailure |
| 原生收到未知/错误类型的模式 | error | debuggerPolicyInvalid |

结构体使用编译时 SDK 声明，不硬编码字节偏移；内存先初始化，只有调用成功且返回长度与 PID
校验通过后才解释标志位。长度/PID 校验能发现部分异常，**不能证明未来 OS 的 ABI 必然兼容**。
不会把失败后的零值解释成正常，也不会在查询失败时退回更弱的条件然后报告“安全”。
原始 PID、标志集合及 errno 不返回 Dart、不记录日志；继续沿用 SDK 的后台队列、超时和取消语义。

## 为什么不使用其他条件替代 P_TRACED

| 条件 | 含义与本次处理 |
| --- | --- |
| Mach exception ports | 只能看到异常处理端口；调试器与崩溃处理器可能都使用，不能仅凭存在性认定已附加，因此不作替代判据 |
| `get-task-allow` | 表示允许调试附加的签名权限，不表示已经附加，不纳入 debugger 判定 |
| `P_SELECT`、普通等待/轮询状态 | 属正常进程行为，不当作逆向或调试器标志 |
| `ptrace(PT_DENY_ATTACH)` | 会改变附加行为，并非只读检测，本库不调用 |

本功能不修改 exception ports，不注入动态库，不终止进程，不添加生产 `get-task-allow`，
不实施自动业务拦截，不依赖第三方指纹或第三方反调试库。

## 验证方法

```sh
sh tool/check.sh
sh tool/check_swift_policy.sh
python3 tool/check_debugger_attach.py
```

- Swift 策略测试在 `-O` 且无 `DEBUG` 和 `-D DEBUG` 两种构建下运行，覆盖默认禁用、显式启用、
  错误配置、截断/扩展响应、错误 PID、权限失败以及真实本进程查询。
- LLDB 验证脚本编译优化的临时夹具，仅附加它自己创建并输出 PID 的进程，检查
  未附加 → 附加并恢复运行 → 解除附加的状态变化。该脚本在 macOS 上运行，用于验证 Darwin 探针，
  不等同于 iOS 真机验证；iOS 原生桥接由 Flutter 集成测试覆盖。
- 测试夹具故意允许调试附加，以便覆盖正例；该测试权限只用于临时产物，不写入 SDK 或宿主项目。
  它不能证明正式分发包可被普通 LLDB 附加。正式分发权限、越狱环境和 Hook 绕过需要分别验收。
- 自动化与构建的实际结果记录在 [roadmap.md](roadmap.md)。模拟器/桌面测试不冒充真机分发验收。

相关依据：[Apple QA1361](https://developer.apple.com/library/archive/qa/qa1361/_index.html)、
[Apple Entitlements Troubleshooting](https://developer.apple.com/library/archive/technotes/tn2415/)、
[Apple task_get_exception_ports](https://developer.apple.com/documentation/kernel/1537860-task_get_exception_ports)。
