# Root / 越狱、Hook、Debugger 与 App Integrity

这四项已从占位接口改为本地检测实现，第三方设备指纹仍不接入。它们是本机可篡改的观察，
不提供“设备绝对安全”证明，不代替 Play Integrity / App Attest 或后端验证，也不自动封禁业务。

## 1. 实际检查内容

| ID | Android | iOS |
| --- | --- | --- |
| `root` | 当前进程 UID=0；已知系统 su / Superuser / SuperSU 路径；test-keys 构建标记；本进程 mountinfo 中框架挂载痕迹 | 真机的已知 Cydia/Sileo/Zebra、MobileSubstrate、SSH/apt、rootless `/var/jb` 等路径；UID=0；已加载 rootless 镜像 |
| `hook` | 当前进程格式有效的 maps 内已知 Hook 动态库精确文件名与可执行映射；当前 ClassLoader 可见的 Xposed/Substrate 类；已知 memfd agent 与 Zygisk 模块来源 | 当前进程 dyld 已加载镜像中的 Frida/Substrate/Substitute/libhooker/ElleKit 等已知精确文件名及注入目录下的已加载 dylib |
| `debugger` | `Debug.isDebuggerConnected`、`waitingForDebugger`；本进程 `TracerPid` | 本进程 sysctl/P_TRACED；原生 Release 需显式选择 `allowReleaseProcessTrace`，默认 unsupported |
| `appIntegrity` | 宿主提供的包名 + 当前 APK 签名证书 SHA-256 集合 | 宿主提供的 Bundle ID + 选定 Bundle 文件 SHA-256 |

- iOS 模拟器的 `root` 返回 `unsupported/simulatorEnvironment`，不把 macOS 开发工具路径判为越狱。
- test-keys、自定义 ROM、测试工具和合法插桩不必然代表攻击。Hook 是已知加载痕迹检查，不覆盖
  重命名/隐藏模块、任意 inline hook、未映射的注入或全部 method swizzling。原生调试器检查不保证识别 Dart VM 服务连接。
- 文件不可观察/权限拒绝、proc 不可读或格式异常、可观察到的 dyld 数量变化不会转换成 `notDetected`。
  dyld 数量相同不证明枚举原子性，动态装卸竞争仍是验证缺口。仅作为非可执行数据映射的同名文件不判为 Hook 模块。
  特别是 iOS 沙箱可能拒绝访问已知路径，此时返回 `error/probeAccessRestricted`。
- 不执行 su/shell，不调用 ptrace 防附加，不写沙箱外测试文件，不 fork，不扫描端口/其他进程/已安装应用。
  对命中原因只返回闭合枚举，不返回完整映射、路径、进程 ID、证书内容或资源哈希。

Apple 的 [QA1361](https://developer.apple.com/library/archive/qa/qa1361/_index.html) 明确建议仅在 Debug
构建使用其依赖不稳定 `kinfo_proc` 结构的示例，因此本库保留 Debug-only 默认值，并为 Release
提供请求级显式启用模式，详见 [iOS Release Debugger](ios_release_debugger.md)。这是一项兼容性取舍，
不是 Apple 对 Release 稳定性的保证。Debug 指插件原生编译条件 `DEBUG`；能力字段
`requiresExplicitOptIn` 指示前提，不把普通 Debug 包本身判为调试器已附加。

## 2. 扫描与缺失基准

```dart
final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-runtime-check',
  detectorIds: SecurityDetectors.runtime,
  timeout: const Duration(seconds: 5),
  integrityPolicy: trustedPolicyForThisPlatform,
));
await sdk.dispose();
```

`AppIntegrityPolicy` 是可选输入。没有基准时，其他检测继续执行，只有 `appIntegrity` 返回
`error/integrityBaselineRequired`。仅提供另一个平台的基准也视为当前平台基准缺失。
`capabilities().supported == true` 表示存在实现，不代表基准已配置或检查一定成功。

基准应来自宿主的可信构建/发布流程或经过宿主认证的配置。**不能从待检查安装包读取当前值并立刻
当作期望值**，否则重打包后的值会被自动信任。SDK 不下载、刷新或持久化基准，不验证配置的远程签名。
不同平台的包名/Bundle ID 不必相同，宿主分别构造本平台的策略即可。

## 3. Android 签名集合与轮换

```dart
final policy = AppIntegrityPolicy(
  expectedApplicationId: androidReleaseApplicationId,
  androidSignerSha256Sets: [
    [approvedCurrentSignerSha256],
    // 经发布流程批准轮换后才加入另一组：
    // [approvedNextSignerSha256],
  ],
);
```

- SHA-256 输入为签名证书 DER 的完整字节；使用 64 位十六进制字符串，不带冒号。大小写会规范化。
  Play 分发时应使用 **App signing certificate**，不要误用 upload key。这里是应用证书摘要，不是设备指纹。
- 外层列表表示可接受的备选集合；内层列表表示同一 APK 的全部当前签名者。例如 `[A,B]` 不等于 `[A]`，
  额外签名者也会导致 `detected/signingCertificateMismatch`，不能“只要一个证书匹配就通过”。
- API 28+：多签读取 `apkContentsSigners`；单签读取 `signingCertificateHistory` 的最后一个当前签名。
  不因某个历史证书匹配就隐式接受所有后续签名。API 24–27 使用 `GET_SIGNATURES`。
- 基准支持最多 8 个备选集合，每组最多 8 个不同证书摘要；重复集合/证书、错误摘要、空策略会被拒绝。
- 包名不匹配 → `detected/applicationIdMismatch`；签名信息缺失 → `error/signingInfoUnavailable`；
  全集匹配 → `notDetected/signingBaselineMatched`。

这是通过 PackageManager 取得的本地签名元数据比较，不重新验证 APK 的所有签名块/每一个安装文件，
不检测所有内存补丁；已被 Hook 的 PackageManager 可能伪造返回值。

## 4. iOS 资源基准

```dart
final policy = AppIntegrityPolicy(
  expectedApplicationId: iosReleaseBundleId,
  iosBundleFileSha256: {
    'Frameworks/App.framework/flutter_assets/assets/config.json': approvedConfigSha256,
    // 对每个真正需要保护的稳定资源分别列出路径和可信构建产物摘要。
  },
);
```

- 这是 **Bundle 身份与指定资源的完整性比较**，不是 Apple 签名证书、Team ID、收据或 App Attest 验证。
  当前未使用 iOS 不提供的 macOS SecCode API，也不把存在 embedded.mobileprovision 当成签名有效。
- 基准只覆盖列出的文件；未列出的内容不在检查范围内。使用发布流水线中的稳定资源，避免对会被
  App Store 加密、重签名或 app thinning 改写的可执行文件/元数据直接套用开发包哈希。
- 路径相对主 App Bundle，拒绝绝对路径、`..`、`.`、空路径段、反斜杠、冒号及控制字符。
  使用目录描述符逐段打开并禁止跟随符号链接；目录、FIFO 等不能充当资源文件。
- 每次最多 32 个文件，单文件最多 16 MiB，总读取量最多 64 MiB。超限 → `error/scanLimitExceeded`，
  不会因读取被截断而返回匹配。文件句柄在成功/失败路径均释放。
- 缺文件 → `integrityFileMissing`，哈希不同 → `integrityFileMismatch`，非法文件类型/链接 →
  `integrityFileInvalid`，均为 detected；读取异常/权限拒绝为 error；全部匹配为
  `notDetected/bundleBaselineMatched`。

资源文件类型检查使用 `fstat`，读取范围限定在宿主 App Bundle；隐私清单已声明
`NSPrivacyAccessedAPICategoryFileTimestamp / C617.1` 并纳入 SwiftPM/CocoaPods 资源。
没有读取或返回文件时间戳，也没有第三方指纹采集。发布前仍应审查实际合并到宿主的隐私清单。

## 5. 执行与资源边界

四项运行时检测及 Android/iOS 多开检测在原生后台串行队列执行，结果回主线程后通过 MethodChannel 返回。Android 允许一个执行中任务
与最多 8 个等待任务；iOS 最多 8 个未完成任务。超过容量时这些项返回 `scanLimitExceeded`；同次扫描
中的其他已完成信号仍保留。Android maps 读取上限 4 MiB，status 上限 64 KiB；mountinfo 上限 2 MiB/16,384 项、32 个 /data 关联挂载；iOS 镜像枚举上限 4096。
没有永久 Hook、动态库注入、后台计时器或自动上报。

Dart 取消/超时/SDK dispose 抑制迟到结果，并不保证中断已开始的所有原生系统调用。
engine detach 后丢弃迟到响应；Android 会中断工作队列，iOS 已提交的有界读取可能完成后才释放。
宿主仍应避免无节制并行扫描，不在每帧触发检测。

## 6. 验证范围

- Dart：策略不可变复制、摘要/路径/身份/数量校验、按需跨桥传参、默认不构造可信基准、错误状态保留。
- Android JVM：多签精确匹配、显式轮换、签名缺失、无效基准、TracerPid 格式、精确模块匹配。
- Swift 原生策略：匹配/篡改/缺文件、路径穿越、末级及中间符号链接、目录/FIFO、大小限制、策略与模块匹配。
- iOS 集成：实际原生扫描、模拟器 root 不适用，以及真实 Bundle 资源匹配/错误哈希/缺文件/错误 Bundle ID。

这些检查不代替 Root/越狱真机、隐藏/重命名 Hook、LLDB/JDWP 附加与解除、Play 签名轮换和 App Store
分发包验收。已执行的测试与构建状态见 [roadmap](roadmap.md)。

## 7. 官方参考

- [Android SigningInfo 与签名历史/多签](https://developer.android.com/reference/android/content/pm/SigningInfo)
- [Android Debug API](https://developer.android.com/reference/android/os/Debug)
- [OWASP Root 检测测试指南](https://mas.owasp.org/MASTG/tests/android/MASVS-RESILIENCE/MASTG-TEST-0045/)
- [OWASP 越狱检测测试指南](https://mas.owasp.org/MASTG/tests/ios/MASVS-RESILIENCE/MASTG-TEST-0088/)
- [Apple required-reason API 类别](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

本轮误报与缺口审查见 [review_findings.md](review_findings.md)。

隐藏 Root/Hook 和多开补充规则见 [hidden_environment.md](hidden_environment.md)。

iOS 多开额外读取自身声明的主文件身份与最多 560 字节 Mach-O 头元数据，不读取代码段或其他应用；
profile 公开 API 版本及保守状态规则见 [ios_oem_multi_instance.md](ios_oem_multi_instance.md)。

混合 runtime 与截图/录屏请求不是原子快照。异步检测期间发生前后台、焦点或观察窗口变化，
capture 项会返回 `error/observationInterrupted`，由宿主在有效上下文中重新发起检测；见
[capture_lifecycle.md](capture_lifecycle.md)。
