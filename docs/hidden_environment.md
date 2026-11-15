# 隐藏 Root / Hook 与多开环境补充检测

这批改动扩大了本进程内可观察痕迹的范围，**不承诺识别完全隐藏的 Root、任意 Hook 或全部多开**。
本批隐藏痕迹规则首次使用 `local-v2`，当前 Android 原生版本为 `local-v7`、iOS 为 `local-v8`（另见 [iOS/OEM 多开](ios_oem_multi_instance.md)）；检测 ID、请求方式和显式扫描约定保持不变。时间/位置的纯 Dart
规则版本不变。没有新增供应商 SDK、设备指纹、网络探测、安装包枚举或自动业务拦截。

## 1. Android Root：本进程挂载表

在既有 UID / su 路径检查后读取 `/proc/self/mountinfo`。匹配框架专用路径边界：
`/data/adb/modules`、`/data/adb/metamodule`、`/data/adb/magisk`、`/data/adb/ksu`、`/data/adb/ap`、
`/sbin/.magisk`、`/debug_ramdisk/.magisk` 的挂载根、挂载点或来源路径。
另外按设备号关联 `/data` 挂载根，识别同一文件系统上 `/adb/modules/...` 这类相对根。
Android local-v7 另检查系统分区（system/system_ext/vendor/product/odm/oem）及子目录的 overlay。
仅解析 lowerdir/upperdir/workdir 的目录值，并要求命中上述框架路径，不匹配 KSU 标签或 context。
先拆分分隔符再解码转义；支持多层和 data-only 双冒号，畸形/重复项及未知转义返回 error。
每条 overlay 最多 256 个选项、每个 lowerdir 最多 128 层。
命中返回 `detected/rootMountArtifact`，只表示当前挂载命名空间中存在已知框架痕迹。

控制误报的边界：

- `/data/adb` 本身是正常系统目录，不作为 Root 证据；普通 `rw`、tmpfs、overlayfs 也不命中。
- 不匹配任意 `magisk` 子串或 App 私有路径中的同名目录；不同文件系统上的 `/adb/modules`
  不在没有 `/data` 关联的情况下判为 Root。
- 不新增对 `/data/adb` 子目录的逐个权限探测，避免将正常沙箱权限拒绝当作阳性。
- 读文件上限 2 MiB、解析上限 16,384 条挂载、关联上限 32 个 `/data` 挂载；超限返回
  `error/scanLimitExceeded`。格式/转义错误或读取失败不转成 notDetected。
- 挂载表被过滤、卸载痕迹、内核完全隐藏、系统调用被伪造仍可能漏检；不能据此确认 Root 不存在。
  自定义 ROM 或合法 Root 使用也可能命中，这不是恶意行为判断。

挂载字段依据 [Linux mountinfo](https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html)。
框架布局依据 [Magisk details](https://github.com/topjohnwu/Magisk/blob/master/docs/details.md) 和
[KernelSU module](https://github.com/tiann/KernelSU/blob/main/website/docs/guide/module.md)。

## 2. Android Hook：已知内存文件与注入路径

仍只读取本进程 maps，并要求格式有效、映射具有执行权限。新增：

| 信号 | 识别条件 | reason |
| --- | --- | --- |
| 已知 memfd agent | `/memfd:frida-agent-{32,64,arm,arm64}.so` 或 `frida-agent.so`，允许内核追加 `(deleted)` | `hookMemfd` |
| 已知 agent 普通文件 | 同组精确文件名，在现有模块名规则基础上补充 | `hookModule` |
| LSPatch 可执行模块 | 精确 `liblspatch.so`，允许 `(deleted)`；数据映射不命中 | `hookModule` |
| Zygisk 模块来源 | `/data/adb/modules/<module>/zygisk/<name>.so` 的可执行映射，即使文件名已更换 | `injectedModulePath` |

普通匿名可执行内存、Dart/ART JIT、一般 memfd、`(deleted)`、可写可执行页或单独线程名均不作
Hook 判据。仅作为数据映射的同名文件也不命中。maps 保留 4 MiB 读取上限，增加
65,536 条映射预算；超限或后续出现损坏行，不能以先前命中替代完整扫描。没有扫描内存内容、其他进程、线程名或端口。

这仍依赖剩余名称/来源痕迹：agent 彻底重命名、复制到普通目录、匿名化并擦除来源、APK 内嵌映射、
inline hook、虚假的 maps 和隐藏 ClassLoader 不保证覆盖。合法调试插桩也可能命中。
已知 agent 命名与 memfd 装载依据 [Frida 上游实现](https://github.com/frida/frida-core/blob/main/src/linux/linux-host-session.vala)，
模块路径依据 [Zygisk 模块说明](https://github.com/topjohnwu/Magisk/blob/master/docs/guides.md)。

## 3. iOS：已加载镜像的来源路径

除现有精确模块名外，检查 dyld 返回的已加载镜像路径：

- `root`：识别 `/var/jb/`、`/private/var/jb/` 和完整随机 preboot 布局下的镜像，返回
  `detected/jailbreakLoadedImage`。随机布局限定十六进制 boot hash、`jb-<6 位字符>` 或
  `dopamine-<6 位字符>`，以及后续 `procursus/`，不把任意 preboot 文件当作越狱。
- `hook`：识别 `/Library/MobileSubstrate/DynamicLibraries/`、`/usr/lib/TweakInject/`
  及其上述 rootless 根下的已加载 `.dylib`，返回 `detected/injectedModulePath`。
  即使 dylib 改名，只要仍从这些已知注入目录装载，就能保留来源信号。
- App Bundle 内的同名子目录、相似前缀、路径穿越、重复分隔符和普通 rootless 库的 Hook 判定均排除。
  普通 rootless 库可以是越狱环境痕迹，但不因此单独判为 Hook。

没有枚举 preboot 目录、解析其他应用数据或写出沙箱。模拟器 root 仍 unsupported；iOS 多开现有局部执行身份探针，见 [专项说明](ios_oem_multi_instance.md)。dyld 枚举最多 4096 项；local-v7 限制字符串读取并复核两轮地址/名称/数量，不一致返回 error，仍不保证原子快照。
动态装卸竞争、重定位到普通目录、完全隐藏镜像和任意函数替换仍需进一步验证。
随机目录依据 [Dopamine 环境管理实现](https://github.com/opa334/Dopamine/blob/2.x/Application/Dopamine/Jailbreak/DOEnvironmentManager.m)。

## 4. Android 多开：结构与身份交叉检查

原先任意 `/virtual/`、`/parallel/`、`/virtualapp/` 子串规则已移除。当前按以下顺序判断：

1. 不是普通应用 UID 的进程返回 `unsupported/unsupportedProcess`，包括常见隔离/SDK sandbox
   进程；不对这类服务强行套用应用身份比对。
2. 有效自身数据目录呈现 `<宿主数据根>/virtual/data/user[_de]/<id>/<客体包名>`，客体包名与
   当前 Context 包名相同且宿主不同 → `detected/virtualContainerPath`。宿主根支持
   `/data/user`、`/data/user_de`、`/data/data` 和 adoptable storage 的 `/mnt/expand` 布局。
3. `Os.getuid()` 与 `ApplicationInfo.uid` 不同，且当前 ClassLoader 可见 VirtualCore 或
   BlackBoxCore 的精确类名 → `detected/virtualContainerIdentity`。类检查不执行静态初始化。
4. 只有 UID 不同，缺少框架证据 → `error/processIdentityMismatch`；自身身份字段缺失 →
   `error/processIdentityUnavailable`。不会猜测是多开，也不会把异常报告成正常。
5. 其余情况按公开 API 版本检查 profile：API 30+ 工作资料保留 `detected/managedProfile`；
   API 35+ 当前非工作 profile 的公开类型精确为 CLONE 时返回 `detected/cloneProfile`。
   API 30 前、API 30–32 非工作资料、其余无法区分的非工作 profile 返回
   `unsupported/profileTypeUnavailable`；仅 API 33+ 非 profile 返回 `notDetected/noKnownSignal`。

只读取当前 Context/进程身份，UID、包名、数据路径和框架类名均不返回 Dart 或日志。
非零 user ID、共享 UID、工作资料和单独打包某个框架类不等于非法多开；工作资料仍有独立 reason。
实际框架版本、定制目录、厂商分身、私密空间、身份 API 被 Hook 和隐藏类的情况需要实机验收。
合法沙箱产品、测试框架或跨用户 Context 也可能提供相同组合证据，故仍不能证明恶意或同时运行了多个实例。

多开检测移到 Android 有界后台队列；`SecurityDetectors.environment` 的 ID 和顺序不变。
无需额外权限或宿主配置。与其它运行时项一起排队时可能返回 `scanLimitExceeded`，不能折算为正常。

## 5. 验证与接入

```dart
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-runtime-check',
  detectorIds: [SecurityDetectors.root, SecurityDetectors.hook, SecurityDetectors.multiInstance],
  timeout: const Duration(seconds: 5),
));
```

对新增 reason 按具体语义展示/上报，不采用 `status != notDetected` 即认定攻击的规则。
新版本 core 与 Flutter 插件需一起升级；旧 core 不识别新增 reason 时应拒绝响应，而不是静默忽略。

自动化覆盖已知/相似路径、转义与损坏数据、挂载关联与预算、普通 JIT/匿名映射、重命名模块来源、
宿主/客体边界、UID 单独异常与交叉证据、共享 UID、次用户、工作资料和桥接状态一致性。
这些是规则和协议回归，**没有证明在真实隐藏 Root、Frida/Zygisk、VirtualApp/BlackBox 或越狱设备上的检出率**。
Android 15 普通只读模拟器已验证真实 maps/挂载读取、普通应用身份及截图生命周期；iOS 模拟器验证原生桥接。
实际测试记录见 [roadmap](roadmap.md)。下一步仍需在授权设备记录正常环境误报率及具体版本的检出表现。

新增来源：[KernelSU metamodule](https://kernelsu.org/guide/metamodule.html)、
[Linux overlayfs](https://docs.kernel.org/filesystems/overlayfs.html)、
[LSPatch 加载入口](https://github.com/LSPosed/LSPatch/blob/master/meta-loader/src/main/java/org/lsposed/lspatch/metaloader/LSPAppComponentFactoryStub.java)。
LSPatch 从 APK 直接加载时，maps 可能只显示 APK 路径，新增名称规则不保证覆盖该模式。
本轮回归结果与单独的真机矩阵见 [hidden_environment_acceptance.md](hidden_environment_acceptance.md)。

2026-11-14 iOS 来源补强、有界采集与真机待验收见 [ios_hidden_review.md](ios_hidden_review.md)。

当前 dyld 安全复制与代际校验、独立真机矩阵见 [ios_dyld_snapshot.md](ios_dyld_snapshot.md)。
