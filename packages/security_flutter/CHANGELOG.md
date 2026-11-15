# 0.1.0-dev.1

- Initial development contracts and bootstrap. Not published.

- Added local environment signal contracts, guarded time/location inputs, and explicit screenshot observation. See repository detection matrix for platform-specific coverage.

- Added explicit release integrity baselines and local runtime detection. Platform
  coverage and iOS Release debugger limitations are documented in runtime_security.md.

- Added per-request iOS Release process-trace opt-in and capability prerequisites,
  with response-size/PID validation and explicit unknown/error handling.

- Tightened Android emulator markers and validated executable Hook mappings;
  malformed proc data is not a negative result. Screenshot windows now invalidate
  on Activity pause or iOS window replacement, with legacy UIKit support.
- Added native status/reason consistency checks and a bounded disposal deadline;
  documented remaining false-positive risks and platform/device coverage gaps.

- Added closed reasons for root mount / loaded-image artifacts, known memfd and
  injection origins, and corroborated container identity; native rules are local-v2.
  Root/Hook/container coverage and false-positive boundaries are documented.

- Native local-v3: add bounded iOS main-executable Mach-O/container identity
  signals, preserve unknown executable formats, and gate Android profile APIs
  by public availability. Unresolved OEM/private profiles remain unsupported;
  new reason codes are validated at the bridge. No supplier fingerprinting.

Native local-v4 tightens active tunnel matching and invalid location metadata
handling. Low-OS framework regressions and an iOS 13 availability check are now
provided; see `docs/compatibility_review.md` in the repository. Unknown location
sources stay unknown. No third-party fingerprinting was added.

Native local-v5 isolates capture lifecycle and cleanup across owners/engines,
invalidates observations across focus/background/window changes, and prevents
stale capture success after asynchronous scans. Failed unregister is retried
without accumulating listeners. Dart late start/stop/dispose races have regression
coverage. Recording remains a snapshot, and Android UID / iOS global screenshot
notification scope cannot establish exact engine attribution. See the repository's
`docs/capture_lifecycle.md`. Third-party fingerprinting remains deferred.

Native local-v6 scopes iOS activation observers to their own Scene (App events only
for legacy hosts), binds capture to Window/Scene/Screen identity, and repairs Android
decor reattachment/focus observation. Android PiP cannot satisfy foreground capture
prerequisites. Geometry-only changes preserve accumulated evidence; real gaps stay
unknown. See `docs/scene_window_lifecycle.md` in the repository for limits and tests.
No third-party fingerprinting was added.


- Added repository test-host fixtures and explicit-device validation for real
  UIKit Scenes, dual-app Android split-screen and AVKit PiP. Runner rejects stale
  build/report success; documented actual passes and unresolved Scene teardown.
  Native detection rules remain local-v6; no fingerprint implementation.


- Corrected the example's real Scene close workflow and named configuration;
  added three-cycle OS teardown and weak engine/plugin/controller reclamation
  evidence. Failed background destruction remains documented, not treated as clean.
  Production local-v6 detection behavior is unchanged.

- Android local-v7: current-user API 35+ CLONE profile detection; private/unknown
  profiles remain unsupported. Add system overlay backing-path Root evidence,
  metamodule paths, executable LSPatch names and a maps entry budget. Extend
  policy/framework/bridge regressions; iOS remains local-v6. Physical hidden/OEM
  validation is separately documented and has not been executed.


### iOS 隐藏环境复核（2026-11-14）

iOS local-v7 补齐 ElleKit 与 rootful 注入来源、统一路径校验、有界 UTF-8 复制与两轮镜像身份核对。
新增 10 项 Swift 回归；完整隐藏与 dyld 并发指针生命周期仍未解决。真机待验收独立记录于
仓库 docs/ios_hidden_review.md。第三方指纹仍不实现。


### iOS dyld 并发复核（2026-11-14，local-v8）

改用本进程内核复制和 dyld 代际校验，移除对 dyld 所有名称指针的直接解引用，保守拒绝 ABA、
忙碌发布数组、权限/短读/未知布局。修复合法系统镜像重复分隔符导致整体误降级。
新增 12 项回归，含真实 macOS dlopen/dlclose 和失效页复制；真机验收单列于
仓库 docs/ios_dyld_snapshot.md。第三方指纹未实现。
