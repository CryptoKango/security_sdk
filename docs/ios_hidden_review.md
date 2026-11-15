# iOS 隐藏越狱 / Hook 复核（2026-11-14）

本页是 local-v7 历史审查；后续 local-v8 已替代裸指针采集并加入代际校验，见 [当前实现与验证](ios_dyld_snapshot.md)。

iOS 原生规则升级到 `local-v7`，Android 保持 `local-v7`。检测 ID/reason/schema 不变。
没有引入第三方指纹、网络、沙箱写入、私有 API、全局 dyld 回调或自动封禁。

## 修复与检测边界

| 缺口 | 本轮处理 | 误报约束 |
| --- | --- | --- |
| ElleKit 原有列表仅包含 ellekit.dylib | 增加精确 libellekit.dylib 名称；固定 /usr/lib/ellekit/libinjector.dylib 来源及已知 rootless/preboot 对应路径 | 泛化 libinjector.dylib、普通同目录库、相似后缀不命中；合法插桩命中只说明模块存在 |
| rootful 隐藏文件探针仍可留下已加载 tweak 来源 | 已加载 MobileSubstrate/DynamicLibraries、TweakInject 的 dylib 和固定 ElleKit injector 来源也可产生 jailbreakLoadedImage | App Bundle 中的同名子目录不算系统来源；不把 App 内 Frida/ElleKit 文件名本身当越狱证据 |
| 模块名匹配绕过了路径合法性检查 | 模块名与来源路径统一检查绝对路径、长度、控制字符、重复分隔符和穿越 | 异常镜像输入是 error，不作为安全或新增风险阳性 |
| String(cString:) 无长度界限且会替换非法 UTF-8 | 最多探测 4097 字节，接受 1–4096 字节且严格 UTF-8 的名称 | nil、空、过长/未终止、非法编码返回 error；不返回原始路径 |
| 前后数量相同仍可替换镜像 | 先复制镜像地址与名称，再复核每项身份和前后数量 | 可观察的不一致覆盖先前阳性/阴性，返回 error；不据此判断 Hook |

上限：4096 个镜像，每个路径 4096 字节，首轮路径总量 2 MiB；两轮扫描不注册进程全局监听。
零镜像/无 header/中途消失等返回 nativeFailure，数量/累计预算超限返回 scanLimitExceeded。
Root 原有 UID/文件信号可能提前返回，验收新增来源 reason 时应排除这些前置命中。
模拟器 Root 仍 unsupported；运行时 Hook 检查不受 Release/Debug 开关改变。

依据：[ElleKit 上游构建安装规则](https://github.com/tealbathingsuit/ellekit/blob/main/Makefile)、
[Apple dyld 接口说明](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html)。
本轮从上游安装路径推导检测规则，不等同于已验证特定越狱版本的检出率。

## 尚未解决的限制

Apple 明确说明按 image count 遍历并非线程安全。二次核对只能发现可观察的差异，不能锁住 dyld，
也不能排除两次观察间移除再加入相同镜像的情况。长度上限不保证被伪造指针或并发卸载的指针生命周期安全。
本轮没有宣称解决原子快照或任意对抗性内存安全；后续需独立评估可用的加载器同步方案与装卸压力测试。

完全过滤 dyld 列表、擦除/重定位来源、未知 RootHide 布局、任意 inline Hook/method swizzling，
以及伪造探针 API/修改 SDK 自身仍可能漏检。未新增 UUID/目录子串、RWX、环境变量、端口等模糊判据。
普通合法开发工具可能加载真实 Hook 库，须保留原因供宿主决策，不能把 detected 一概理解为攻击。

## 自动化与真机验收分开

`RuntimePolicyTests.swift` 新增 10 项：精确 ElleKit/系统来源、App 目录负例、非法路径、C 字符串
边界/UTF-8、稳定镜像、nil/零/超限、同数量地址或名称替换、数量变化、中途消失、累计预算。
`sh tool/check_swift_policy.sh` 验证纯策略与受控采集输入，不模拟真实 dyld 并发卸载。
`sh tool/check_ios_minimum.sh <flutter_sdk>` 验证 iOS 13 可用性/类型，不等于 iOS 13 真机运行。
本轮实际执行结果见 [roadmap](roadmap.md) 最新记录。

下列真机项目全部待执行，不以策略测试或构建成功标记通过：

| 编号 | 场景 | 对照与验收重点 |
| --- | --- | --- |
| IOS-R1 | 授权 rootful / rootless 越狱，固定工具及 OS 版本 | 文件可见/隐藏开关前后对照；记录当前进程可见来源与具体 reason，不把漏检写成安全 |
| IOS-H1 | ElleKit、Substrate、Frida 各固定版本 | 注入开/关、原名/改名、标准来源/重定位；分别记录 Root 与 Hook；App 内合法插桩不能单凭名称判越狱 |
| IOS-H2 | 完全隐藏 dyld/未知 RootHide 布局 | 建立实验环境真值，记录漏检和 unknown；不承诺全部覆盖 |
| IOS-N1 | 正常 iPhone/iPad，开发/企业/TestFlight/商店渠道 | Debug/Release、普通 framework/Swift 库、合法测试工具；普通路径不得产生来源阳性 |
| IOS-L1 | 授权测试宿主并发 dlopen/dlclose 可卸载测试镜像 | 重复 Root/Hook 请求，观察不一致的 error、延迟与崩溃；策略替换夹具不能替代此项 |
| IOS-L2 | 多 engine、前后台、低版本与当前 OS | 重复扫描/销毁，不新增全局状态与日志路径泄漏；与已有截图/Scene 验收分开记录 |

顺序：先正常负例，再明确正例，最后隐藏组合和并发装卸压力。记录人工设备代号、OS/工具版本、
构建编号、规则版本、模式、status/reason、重复次数、passed/failed/blocked；不上传原始路径/指针。
第三方指纹继续不实现。无法准备设备或正例真值时记 blocked，不记已通过。
