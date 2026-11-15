# iOS dyld 指针生命周期与扫描一致性（2026-11-14）

当前 iOS `local-v8`，Android 保持 `local-v7`。本轮替代 v7 的逐索引 dyld 指针读取。
检测 reason/schema、显式请求、每 engine 的所有权及第三方指纹范围不变。

## 根因和处理

v7 从 `_dyld_get_image_name` 获得 dyld 所有的指针。即使限制 strnlen 长度，卸载线程也能在
获取指针和读取之间释放它；比较前后数量/地址不能消除这次直接读取的风险，也会漏掉 ABA 装卸。

现在 `RuntimeSignals` 使用 `DyldImageSnapshot`：

1. 通过公开 `task_info(TASK_DYLD_INFO)` 获取**本进程** dyld 信息地址；不取得其他任务端口。
2. 用 `vm_read_overwrite(mach_task_self_, ...)` 将元数据、镜像数组和名称复制到 SDK 自有缓冲区。
   Swift 不解引用镜像 header 或 dyld 名称指针，也不调用旧的逐索引 getter。
3. 只接受已知 64 位结构布局 version 15–18，检查提供的结构尺寸；仅复制到变更时间戳字段的公共前缀。
   未知布局、零时间戳、空发布数组、读取失败/短读保持 error，不回退到不安全读取。
4. 复制前、复制后、结果返回前比较结构地址/版本、数组地址/数量及 `infoArrayChangeTimestamp`。
   数量和地址恢复原值但 generation 变化仍使结果失效；只对 SDK 自有不可变镜像值应用规则。
5. 名称按 VM 页边界分块复制，严格 UTF-8，拒绝空值、越界、未终止、非法地址；受保护/已释放页由
   内核返回失败，不通过进程信号处理器吞掉异常。普通路径的重复 `/` 做词法归一化，仍拒绝 `.`/`..`、
   相对路径及控制字符，不解析符号链接。此项修复了真实系统镜像因重复分隔符被整体误降级的问题。

仍限制 4096 个镜像、每名称最多 4096 字节、名称累计 2 MiB。无无限重试；忙碌/变化返回
`error/nativeFailure`，保护失败为 `probeAccessRestricted`，预算超限为 `scanLimitExceeded`。
不将变化本身视为 Hook，不将 error 视为正常。没有全局回调、镜像缓存、dlopen 保活、锁住/暂停线程、
修改动态库引用计数或新增网络/权限。测试使用 dlopen，生产 SDK 不使用它。

依据：[Apple dyld 公共结构及发布约定](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_images.h)、
[Apple 镜像信息实现](https://github.com/apple-oss-distributions/dyld/blob/main/libdyld/dyld_process_info.cpp)、
[XNU VM 接口](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_map.defs)。
未调用私有 `_dyld_process_info_create` 或 dyld 内部锁。实现仅使用 SDK 公开声明的 Mach 接口和结构。

## 一致性的准确含义

解决的是 SDK 对可失效 dyld 指针的直接解引用，以及同数量/同地址 ABA 变更漏检。
依赖系统发布数组和变更标记的语义，验证采集期间可观察到的代际稳定性；不暂停加载器，
不承诺结果返回之后环境仍不变化，也不提供对被 Hook 的内核接口/被伪造元数据的完整性证明。
请求恰逢装卸可能返回未知，这是预期的保守结果。未知系统布局也不会猜测为正常。

## 已执行回归

- 新增 `DyldSnapshotTests.swift` 12 项：稳定代际、ABA、返回前变化、忙碌数组、预算、短读/权限错误、
  分隔符别名、跨页末尾终止符、不可读/已解除映射地址、真实装卸和静止后恢复。
- `tool/check_dyld_snapshot.sh` 编译临时 C-only dylib，先确认实际加载、实际卸载和两次代际变化，
  再并发执行 1000 轮装卸与 300 次扫描。最新完整运行：131 次未见信号、169 次未知、零风险阳性，
  无崩溃，静止扫描正常；计数受调度影响，不作为固定测试预期或检出率。
- 实测发现测试输入与 dyld 路径存在别名，先后出现断言失败；已将两边测试路径规范化后保留实际移除
  断言。随后发现普通系统镜像的重复分隔符，修复后才通过静止可用性验收。没有把失败改记为通过。
- 新测试已纳入 `sh tool/check_swift_policy.sh`，完整 101 次 Swift 测试执行通过。
- `sh tool/check.sh`：60 项 Dart/Flutter、25 项 Python、格式与静态分析通过。
- iOS 13 arm64 可用性/类型检查通过；Release 集成构建结果记录于 roadmap。

上述实际 dlopen/dlclose 压力运行在 macOS 主机，使用真实 dyld 和 VM 接口；不是 iOS 真机验收。
没有执行 iOS 模拟器集成、真机、Android JVM 或 XCTest。本轮不修改 Android 检测规则。

## 独立真机验收：全部待执行

| 编号 | 场景 | 必须核对的证据 |
| --- | --- | --- |
| D1 | iOS 13 至当前版本、arm64/arm64e，普通 Debug/Release 宿主 | 公共结构版本/权限确实可用；静止扫描能完成，不能全部 error；不上传指针/路径 |
| D2 | 自有签名测试宿主内可卸载 C-only 动态库 | 确认真机确实加载/卸载并改变 generation，再并发扫描；不以 dlclose 返回成功代替实际移除 |
| D3 | 多 engine、前后台切换、扫描取消/销毁 | 独立请求无共享可变快照；完成/未知/超时符合既有协议，无悬挂及异常增长 |
| D4 | 正常应用合法 framework/Swift 库、测试工具 | 路径别名不造成整体误降级；普通装卸不产生风险阳性，合法 Hook 仍保留具体 reason |
| D5 | 授权越狱/注入环境与隐藏开关 | 新采集通道中的来源信号是否可见；受限/伪造环境不宣称全覆盖；分别记录漏检与错误 |

先 D1/D4 负例与静止可用性，再 D2/D3 并发，最后 D5。记录人工设备代号、OS/构建/规则版本、
实验模式、实际装卸证明、status/reason、次数、延迟/内存及 passed/failed/blocked，不上传原始地址。
无设备、库实际不能卸载或无法建立正例真值时标 blocked。已有隐藏越狱/Hook 真机矩阵继续有效。
第三方指纹仍然不实现。
