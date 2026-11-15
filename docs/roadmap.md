# Implementation status

- K01: independent workspace and official package/plugin skeletons created;
  package name ownership, remote repository, publisher and license remain pending.
- K02: pure Dart contracts, closed reason codes, guarded time/location inputs and
  test fake implemented; API review and richer provider proof semantics pending.
- K03: scanner facade, cancellation/deadline/disposal, defensive channel parsing,
  per-owner explicit screenshot windows and native lifecycle cleanup implemented.
  General event streams, full multi-engine/device lifecycle validation pending.
- K04/K05: first local environment signals implemented. See detection_coverage.md
  for exact platform coverage, heuristics, OS gates and host-input prerequisites.
  Root/jailbreak and known-hook indicators, Android debugger checks and explicit
  host-baseline app integrity are implemented. iOS Release debugger process-trace
  checks support explicit per-request opt-in; the default remains Debug-only;
  iOS integrity covers Bundle ID and selected resources, not signing attestation.
  See runtime_security.md and ios_release_debugger.md for limits and setup.
- K06/K07: third-party fingerprinting explicitly deferred by request; optional
  platform attestation packages also not implemented.
- K08: plain Flutter scan and screenshot start/read/stop example provided;
  real host business integration pending. No host-specific business gates added.
- K09/K10: local checks and native integration test entry points provided; CI,
  complete compatibility matrix, hosted consumers and publishing review pending.

## Verification on 2026-11-13 (current local-v4)

- Formatting and Dart/Flutter static analysis: passed.
- Android library lintDebug: passed with 0 errors; AGP and Robolectric upgrade advisories remain.
  Optional host permissions are checked explicitly. MissingPermission suppression
  is limited to three guarded methods because the SDK does not merge those
  permissions into every consumer manifest; runtime exception conversion remains.
- Dart/Flutter logic and bridge/lifecycle tests: 52 passed (16 core + 36 Flutter).
- Android JVM tests: 61 passed (31 native policy + 30 framework compatibility executions).
  Robolectric 4.16.1 covered API 24/28/30/31/33/34/35, plus legacy signing on API 24/27.
  These are framework fixtures, not device, ROM or FlutterEngine execution.
- Native Swift policy/resource-isolation tests on macOS: 16 passed, plus 8
  process-trace tests each in optimized non-DEBUG and DEBUG builds, 15 container
  filesystem cases, 7 Mach-O parser cases and 8 compatibility cases (62 executions total).
- All plugin Swift sources passed arm64 iOS 13 availability/type checking with
  tool/check_ios_minimum.sh. No iOS 13 runtime was installed or executed.
- Optimized non-DEBUG Darwin fixture on macOS: actual LLDB untraced/attached/
  detached transitions passed. Test-only attach entitlement stays in temporary
  output; production signing settings are unchanged.
- An additional standalone optimized iOS Simulator attach fixture could not be
  launched (launchd spawn denied, code 163); that positive attach test is not
  counted as passed. The retained attach script targets macOS only.
- Android debug APK: rebuilt with SDK 36 / AGP 9.0.1 for native
  integration validation. Current Android plugin sources passed 61 JVM tests.
- iOS simulator Debug and device-architecture Release (unsigned) builds: passed
  using Xcode 26.6. Compilation is not signed device execution.
- iOS 26.5 simulator integration: 2 API/lifecycle tests passed using Flutter
  drive: environment and runtime scans, screenshot ownership/cleanup, missing
  integrity baseline, real bundle-file match/mismatch/missing/wrong-ID cases,
  debugger capability/default policy and explicitly enabled native self-query.
  This is not a rooted/jailbroken-device or positive-capture efficacy test.
- Device screenshot/recording positive cases, older OS versions, actual profiles,
  automation services, network configurations and real/mock location flows still
  require the manual acceptance matrix in detection_coverage.md. Root/jailbreak,
  hidden/renamed hooks, debugger attach/detach, Android signing rotations and
  store-distributed resource baselines also need real-device validation.

Public release and application risk enforcement are separate milestones. Do not
copy private host architecture documents or business-specific policies here.

## Earlier review follow-up (historical validation)

The local detector review tightened emulator and Hook mapping heuristics, native
result semantics and screenshot observation lifetime; legacy UIKit foreground
handling and bounded disposal were added. See review_findings.md for fixed
issues, residual false positives and ordered device acceptance work. No supplier
fingerprinting, platform attestation, publication or business blocking was added.
The 46 Dart/Flutter tests, 13 Android JVM tests, 28 Swift test executions, 2 iOS
simulator integration cases and unsigned device Release build were rerun after
this review. The LLDB fixture results above are from the preceding debugger work.

## Earlier hidden-environment follow-up (historical local-v2 validation)

Native rules added framework-specific root mounts (including /data
filesystem-relative roots), known executable memfd agents, Zygisk module origins,
iOS rootless/injection image origins, and corroborated Android container identity.
Generic anonymous/JIT memory, writable mounts, ordinary user directories and UID
mismatch alone are not positive hidden-environment findings. Native wire rule
version for that batch was local-v2; core input-only rules remain local-v1. See hidden_environment.md.

49 Dart/Flutter tests, 25 Android JVM tests and 32 Swift test executions passed.
The 2 iOS simulator integration cases and unsigned iOS device Release build passed
again. Hidden/rooted/jailbroken-device positive efficacy and actual cloning product
versions remain unverified; fixtures test the rules rather than those products.

Android 15 / API 35 read-only emulator integration: both API/lifecycle cases
passed, including the real proc maps reader, root mount parsing, normal container
identity, screenshot windows and runtime findings. The capture fixture now
produces an Android first frame before starting observation; the initial run
without it failed the foreground prerequisite. No production foreground gate was
relaxed. The temporary emulator instance was isolated from physical devices.

## Earlier iOS / OEM multi-instance follow-up (historical local-v3 validation)

Added a bounded self-execution probe for iOS APPL bundles: main-executable Mach-O
library type, or corroborated embedded guest bundle / separate host file identity.
Only the declared main executable header is inspected; ordinary bundled dylibs,
symlink/hardlink aliases, extensions, scenes, signing channels and unexplained
path differences are not clone verdicts. CPU/header-width mismatches and malformed
headers remain errors; unknown formats/ambiguous fat slices remain unsupported.

Android now gates isManagedProfile at public API 30 and isProfile at API 33.
Unknown or unclassifiable profiles remain unsupported/profileTypeUnavailable;
private space and OEM clone profiles are not guessed from numeric IDs or brands.
No privileged/hidden APIs, supplier fingerprinting or device enumeration were added.
See ios_oem_multi_instance.md for sources, exact reasons and remaining gaps.

52 Dart/Flutter tests, 31 Android JVM tests and 54 Swift test executions passed.
The 2 Android API 35 and 2 iOS 26.5 simulator integration cases passed, including
normal multiInstance noKnownSignal and local-v3 bridge output. iOS unsigned
arm64 Release compiled using Xcode 26.6; this is not signed device execution.
Actual iOS containers, OEM clone/private/work profiles, older OS API gates on real
systems and distribution-channel false-positive rates remain unverified.

## Low-OS and false-positive follow-up (local-v4)

Invalid/default/non-finite location accuracy no longer produces a source verdict;
invalid/future elapsed time is rejected and Android nanoseconds round up to
milliseconds. iOS rejects non-finite accuracy/age and millisecond overflow before
reading source metadata; absent source information stays null. iOS tunnel signals
require numeric interface suffixes, UP/RUNNING and an IP address family, with
bounded names and a 1024-entry budget. This is still a tunnel heuristic, not VPN
traffic attribution. See compatibility_review.md for the precise limits.

The simulator integration test now handles expected unsupported capture/profile
results on older Android, with exact OS-boundary assertions in the framework suite.
Final validation: 52 Dart/Flutter tests, 61 Android JVM tests, 62 Swift executions,
2 iOS simulator and 2 Android API 35 emulator integration cases passed. Full plugin
iOS 13 availability/type check, Android lint (0 errors / 2 upgrade advisories),
Android debug APK and unsigned iOS arm64 Release build passed.

Initial framework downloads failed POM checksum validation for API 34/35. They
were not accepted or counted as test passes. Official Maven Central artifacts were
re-fetched/verified, and the complete default suite then passed. SHA-512 checking
was not disabled; framework dependencies are test-only and cached locally.

Older-device execution, manufacturer-specific behavior, real location permissions,
physical capture/recording and active network configurations remain manual work.
No third-party fingerprinting, automatic collection, publication or host business
enforcement was introduced.

## Capture lifecycle and multi-engine follow-up (local-v5)

Capture owners remain engine-local. Dart revisions prevent old timeout/stop replies
from cleaning newer windows; delayed custom-provider completion triggers bounded
cleanup when observation is no longer wanted. Android pause/focus/window changes
and iOS App/Scene/window interruption invalidate observations until explicit start.
Unregister failures preserve a bounded retry handle instead of accumulating listeners.
Mixed asynchronous runtime scans cannot return stale capture success across a gap.

Integration found that the current Flutter embedding's Activity focus path does
not forward binding focus listeners. Android now also observes the native decor
ViewTreeObserver, releases it on detach and handles pre-attach observer merging.
A real Dialog focus transition verifies this path; iOS NotificationCenter injection
verifies actual observer wiring and stop/restart without claiming physical capture.
Platform scope and unresolved host cases are detailed in capture_lifecycle.md.

Final validation (2026-11-13):
- `sh tool/check.sh`: clean format/analysis, 59 Dart/Flutter tests (16 core + 43 Flutter).
- Android JVM: 78 executions (31 pure policy + 30 compatibility + 17 lifecycle),
  zero failures/skips. Android lint: 0 errors, 2 existing dependency upgrade advisories.
- Swift: 71 executions including 9 new capture lifecycle cases; macOS policy tests,
  not iOS device executions. Full plugin arm64 iOS 13 availability/type check passed.
- Android API 35 emulator and iOS 26.5 simulator: 4 integration cases each, including
  two real headless FlutterEngine create/destroy cycles alongside the foreground engine.
- Android debug APK, iOS simulator Debug and unsigned arm64 iOS Release built.
  iOS Release binary checked to exclude debug integration channel names.

Initial Android integration attempts correctly rejected capture while an emulator
System UI ANR dialog held focus. After dismissing that system dialog, tests ran
normally; no foreground guard was relaxed. The first synthetic binding focus test
exposed the embedding forwarding gap above, which was fixed and verified with a
real OS dialog. iOS example Debug configuration now explicitly enables its test-only
fixture; those channels are absent in Release. No physical device was used.

Still unverified: physical screenshot/recording positives, legacy UIKit and concurrent
visible Scenes/engines, OEM lifecycle behavior, rotation/PiP/split-screen matrix and
OS service cleanup guarantees. No fingerprinting, publishing or host enforcement.

## Multi-Scene, rotation, split-screen and PiP follow-up (local-v6)

Scene-backed iOS observations subscribe only to their own Scene/window events;
legacy hosts still use App lifecycle events. Window/Scene/Screen identity must
remain the same, including during asynchronous runtime scans. Android now tracks
decor detach/reattach, reinstalls focus listeners, rejects PiP as a foreground
capture context and keeps async context references weak. A gap first observed at
reply time also invalidates the original owner without interrupting newer windows.
Geometry-only changes preserve evidence; rotation/split-screen/PiP are not risk
positives. See scene_window_lifecycle.md for host sequencing and residual limits.

Final validation (2026-11-13):
- `sh tool/check.sh`: format/analysis clean; 59 Dart/Flutter tests (16 + 43).
- Android: 91 JVM executions (31 policy + 30 compatibility + 30 lifecycle), no
  failures/skips; lint 0 errors / 2 existing upgrade advisories. 13 new lifecycle
  executions cover configuration rebuild, geometry preservation, split pause,
  PiP prerequisite failure, decor remount and async PiP gaps.
- Swift: 79 executions, including 8 new Scene/context lifecycle cases. macOS native
  policy tests and full plugin arm64 iOS 13 type/availability check both passed.
- Android API 35 emulator: 6 integration cases; actual OS rotation and PiP entry,
  capture refusal, foreground restoration and explicit restart included.
- iOS 26.5 simulator: 5 integration cases; Scene-bound App-notification isolation,
  actual system rotation, original capture wiring and real headless-engine cycles.
- Android debug APK, iOS simulator Debug and unsigned arm64 iOS Release built;
  Release binary excludes the debug integration channel. Example PiP manifest
  opt-in is Debug-only and does not change the library manifest.

The test fixture was corrected after invalid synthetic Scene objects triggered
UIKit's own notification observers; foreign Scene tests now use an isolated native
NotificationCenter. Device integration injects only appropriate objects/events.
Android PiP restoration uses a launcher-style intent and waits for a stable resumed,
focused, non-PiP state before restarting capture. No production guard was loosened.
Early system-UI ANR on the emulator was dismissed before valid foreground testing.

This is not physical capture efficacy or a real dual-Scene / dual-app split-screen
acceptance run. Concurrent iPad Scenes/Stage Manager, legacy UIKit execution,
physical/OEM split-screen and external-display transitions, and iOS AVKit PiP
content remain outside the verified matrix. No fingerprinting or publication.


## Real OS window validation follow-up (local-v6 unchanged, 2026-11-13)

Added Debug-only independent UIKit Scene/FlutterEngine and offline AVKit fixtures,
a separate permission-free Android companion APK, and an explicit-device runner.
See [real_window_validation.md](real_window_validation.md) for commands and the
physical-device matrix. No production detector, wire schema or fingerprint changes.

Executed results (these are separate test layers, not a device coverage percentage):
- `sh tool/check.sh`: format/analysis clean; all 59 Dart/Flutter tests passed.
- Python runner/report regressions: 13 passed (now included in `tool/check.sh`), including build failure refusing any
  installed binary, corrupt JSON, missing native callbacks and invalid evidence.
- XCTest RunnerTests: 4 passed on the iOS 26.5 iPad simulator test clone, exercising
  actual native bridge headless/unknown/invalid owner/idempotent stop behavior.
- **Android dual-app split passed**, API 35 tablet emulator: both real APKs reported
  multiWindow; companion focused, main resumed but unfocused; SDK returned
  error/observationInterrupted and rejected start; closing companion restored
  fullscreen/focus/resumed, followed by successful explicit start/scan.
- **iOS AVKit PiP passed**, iOS 26.5 iPad simulator: real didStart/didStop counters
  1/1, active true then false, main Scene stayed active with no audit interruption;
  SDK did not manufacture a screenshot positive. Player disposal was asserted.
- **iOS multi-Scene full scenario FAILED**: real distinct Scene and child engine
  connected; child start/scan succeeded, inactive primary correctly returned
  observationInterrupted, primary reactivation succeeded. After one real UIKit
  destruction request, no disconnect callback/notification arrived within 20 s,
  the session remained registered and the engine teardown assertion failed.
  Reproduced after uninstall/reinstall of the synthetic example on the dedicated
  simulator; stale example sessions do not explain that repeat.
  The cause is not established; this is not a clean result or a confirmed SDK bug.
  No simultaneous dual-active Scene or successful OS-driven teardown is claimed.

Sanitized evidence: [Android split](validation_runs/2026-11-13/android_split.json),
[iOS PiP](validation_runs/2026-11-13/ios_pip.json),
[iOS Scenes failure](validation_runs/2026-11-13/ios_scenes.json).
Reports contain test state only, no device IDs, user content or raw detection evidence.

Initial Android attempts crashed in the companion because a custom ResultReceiver
subclass could not be unmarshalled across APKs. It is now converted to the framework
Parcelable type in both directions; missing peer reports fail instead of appearing
as OS limitations. A separate iOS attempt exposed Flutter drive falling back to an
installed binary after a Swift build error. That result was invalidated; independent
build success plus an explicit application binary is now mandatory. Valid results
above were rerun through that gate. No production foreground checks were relaxed.

Remaining work, in order:
1. Diagnose actual iPad Scene destruction/disconnect using a clean simulator and
   physical iPad; retain the failing teardown assertion until real cleanup occurs.
2. Execute M1 dual-active/Stage Manager and M2 migration/teardown stress matrix;
   connected scenes alone do not prove independent simultaneously active windows.
3. Validate Android 24–31/manual split, OEM/freeform distinctions, divider resizing
   and physical capture positives. Automatic LAUNCH_ADJACENT needs API 32+.
4. Execute iOS PiP Home/background/lock/unlock with native UI automation or manual
   driving; Flutter VM service survival is not a lifecycle guarantee.

Unsigned arm64 iOS Release rebuilt successfully. Its final Info.plist has no test
multi-Scene opt-in or audio background mode; its executable contains neither
fixture channel names nor the test Scene/PiP class names. Debug setup stays in the
example host, not the published SDK. Android companion was uninstalled from the
dedicated emulator after validation; no connected physical device was targeted.

Previous 91 JVM and 79 Swift policy executions are historical local-v6 checks, not
new executions in this follow-up. No physical device, publication or backend action.


## Scene close and engine reclamation follow-up (local-v6 unchanged)

2026-11-13: the earlier failure was traced to SpringBoard vetoing destruction of
an inactive target Scene in this iOS 26.5 iPad simulator. No system disconnect had
occurred for the SDK to observe. Direct background destruction still failed after
named-configuration correction and six stable activation samples; this behavior
is not claimed to apply to every iOS version. No private API or fake callback is used.

The Debug host now requires the target to be active before issuing destruction;
the regression explicitly activates it with UIKit and then waits for actual OS
completion. Inactive calls return fixture_scene_inactive without sending a request.
The SDK itself never activates or closes host windows. Independently corrected:
- Complete named Scene configuration in Debug plist, returned without mutating its
  delegate/storyboard (which cleared the name in this UIKit). Actual session name
  is asserted. Temporary test Scenes do not restore stale activity/token state.
- FlutterSceneDelegate forwarding and one idempotent cleanup path. The optional
  AppDelegate discard callback records system evidence without invoking an
  unimplemented superclass method in the current Flutter embedding.
- Session presence is checked against the stored original session identity, not
  inferred from a window reference that cleanup has already cleared.
- Separate weak engine/plugin/controller/window probes and isolate destruction
  evidence; calling destroyContext alone is insufficient proof of reclamation.
- setup/cleanup exceptions explicitly fail the report even if Flutter drive prints
  a successful summary. The Python validator requires all three complete rounds.

Verified real OS run: **three consecutive create/activate/close/reclaim rounds passed**.
Each round observed one sceneDidDisconnect and one cleanup, a discarded session
absent from openSessions/connectedScenes, and all weak resource references cleared.
The child SDK was observing at engine teardown (not disposed beforehand). Repeated
close was idempotent and commands to the closed child were rejected. Main Scene's
old observation stayed error/observationInterrupted until an explicit restart;
each new child required a fresh start. Final fixture registry count was zero.

Evidence: [three rounds](validation_runs/2026-11-13/ios_scene_cycles.json),
[background rejection after configuration/stability checks](validation_runs/2026-11-13/ios_scene_background_rejection.json),
[PiP regression](validation_runs/2026-11-13/ios_pip_after_scene_fix.json).
Original failed reports remain historical evidence, not converted to passes.

`sh tool/check.sh`: clean format/analysis, 59 Dart/Flutter and 25 Python regressions
passed. Five native XCTest cases passed, including the actual Debug named Scene
configuration/delegate check. Real iOS PiP start/stop also passed after the Scene host changes. Physical
screenshots, simultaneous dual-active Scene isolation, background direct destruction,
Stage Manager, old OS runtime and physical iPad acceptance remain separate work.
No production detection-rule changes, third-party fingerprinting, publication or
backend actions. See real_window_validation.md for the reproducible procedure.

Release follow-up: unsigned arm64 iOS build passed. Final plist excludes the test
Scene configuration/multi-Scene/audio opt-ins; the executable excludes both test
control channels and Scene/PiP fixture classes. No production rule was relaxed.
The report validator also accepts dual-active operation without a main-Scene
interruption; this is a policy regression, not an executed dual-active OS claim.

## Hidden Root/Hook and OEM profile follow-up (2026-11-13)

Android now reports local-v7; iOS remains local-v6. Added bounded system-overlay
backing-directory evidence (including metamodule paths), executable LSPatch module
names and a maps entry budget. API 35+ queries only the calling user's public
LauncherUserInfo type, reporting cloneProfile only for the exact CLONE type;
private/unknown/null profiles remain unsupported and denied access remains error.
No permissions, user enumeration, network or third-party fingerprint SDK was added.

Verified: 105 Android JVM tests (38 policy, 37 framework, 30 lifecycle); Android lint
0 errors and two dependency-update warnings. `sh tool/check.sh` passed 16 core,
44 Flutter and 25 Python tests with clean analysis/format. Framework tests use
controlled responses and an Android app UID fixture, not the host JVM UID.
No physical device, new emulator run or iOS native rerun is claimed this round.
The simulator integration version assertion now distinguishes Android v7 / iOS v6.

Remaining device cases, positive/negative controls and execution order are tracked
separately in [hidden_environment_acceptance.md](hidden_environment_acceptance.md).
Fully hidden/renamed hooks, filtered mount/maps and nonstandard OEM clones remain
coverage gaps; ordinary profiles or unknown results are not maliciousness verdicts.

## iOS hidden jailbreak / Hook follow-up (2026-11-14)

Both native platforms now report local-v7; only iOS production rules changed in
this round. Added exact ElleKit library/injector evidence and known rootful loaded
tweak origins, unified path validation, bounded UTF-8 image-name copying, and
best-effort header/name/count revalidation with a 2 MiB aggregate path budget.
The protocol/reasons and explicit request model are unchanged.

Executed: 89 Swift test executions (26 runtime/integrity, 16 Debug/Release tracing,
15 container, 7 Mach-O, 8 compatibility, 17 capture); 10 runtime cases are new.
iOS 13 arm64 availability/type check passed. Unsigned arm64 iOS Release application
build passed. `sh tool/check.sh` passed format/analysis, 60 Dart/Flutter and 25 Python
tests. No physical-device, simulator integration, XCTest or Android JVM rerun is
claimed this round. Existing Android production rules were not changed.

[Separate iOS physical-device acceptance matrix](ios_hidden_review.md) remains
pending. Same-count replacement fixtures do not establish an atomic dyld snapshot
or pointer safety under concurrent unloading. Fully hidden images, unknown layouts
and arbitrary hooks remain gaps. No third-party fingerprinting or publication.

## dyld snapshot ownership and generation follow-up (2026-11-14)

Production iOS local-v8 now copies only self-task dyld metadata through public
TASK_DYLD_INFO / vm_read_overwrite into owned buffers. It no longer dereferences
loader-owned names or uses per-index getters. Public layout/size, page-aware name
copying, bounded arrays/strings, and metadata generation checks reject incomplete
or changing snapshots, including same-count/address ABA changes. Redundant path
separators in real system image metadata are normalized without permitting traversal.
No global callbacks, image pinning or changes to host loader reference counts.

Executed: 101 Swift test executions including 12 new snapshot regressions; real
macOS C-only dylib load/unload/generation verification, followed by 1000 load/unload
cycles concurrent with 300 scans. Latest full run returned 131 notDetected and 169
error, zero risk positives; quiescent scanning recovered and the fixture was truly
removed. Scheduler-dependent counts are evidence, not fixed expected values.
The new runner is included in tool/check_swift_policy.sh.

Also passed: sh tool/check.sh (60 Dart/Flutter, 25 Python, format/analysis), iOS 13
arm64 type/availability check, and unsigned arm64 iOS Release build. iOS device,
simulator integration, XCTest and Android JVM tests were not run this round.
[Detailed limitations and separate pending device matrix](ios_dyld_snapshot.md).
Version 15–18 public metadata layouts are accepted; other layouts stay unknown.
This is generation-validated observation, not a freeze of the process or proof
against forged APIs. Third-party fingerprinting remains unimplemented.

## Runnable integration example (2026-11-14)

Added root `example/` as an independent Android/iOS demo in the pub workspace;
`test_apps/native_validation` remains the existing native validation host. The demo
uses only public SDK APIs, performs no collection at construction, serializes
manual operations, displays status/reason/version without raw evidence, defaults
iOS Release debugger opt-in to off, and explicitly restarts capture windows.
Host-input checks are separated from the local scan; the missing-input button
shows errors while `host_input_example.dart` accepts real host-provided inputs.
No third-party fingerprinting, backend, location acquisition or enforcement.

Verified: repository format/analysis; 67 Dart/Flutter tests (16 core, 44 plugin,
7 demo behavior tests) and 25 Python tests; new demo Android Debug APK and unsigned
iOS arm64 Release build. No device installation or runtime efficacy acceptance.
The standard tool/check.sh now includes the demo. Setup and platform boundaries:
[example/README.md](../example/README.md).

## Complete example API and simulator acceptance (2026-11-14)

The root example now demonstrates all 14 shipped detector IDs, individual/all
scans, capability discovery, cancellation/timeouts, start/stop/restart and explicit
disposal, host-input injection and pure Dart evaluation helpers. Abstract monitor
and evidence-provider contracts are explicitly distinguished from implemented APIs.

Executed Android API 35 and iOS 26.5 simulator integration: scan/input failures,
real foreground/background transitions, interrupted capture windows, explicit
restart and disposal all passed. Android SystemUI MediaProjection recording
changed from detected to notDetected on stop. Screenshot exports and iOS simctl
video export do not establish positive capture notification coverage.

76 Dart/Flutter and 34 Python regressions passed. The runner rejects empty or
partial evidence and retains failed attempts. See [results and separate physical
acceptance checklist](example_device_validation.md). No native detection rules,
fingerprint provider or backend were added.

## Flutter 3.38.10 through current stable compatibility (2026-11-14)

SDK and portable example now declare Flutter >=3.38.10 / Dart >=3.10.9 <4.0.0.
Android plugin inherits host tooling, applies external KGP only on AGP 8 and uses
Flutter’s current KGP migration bridge on AGP 9. Pure built-in mode is not required for the full supported range. Example tooling follows each selected Flutter template;
CocoaPods retains Scene lifecycle. The advanced native fixture resolves separately
and retains Flutter 3.44.9 as its minimum.

Executed isolated matrices on 3.38.10, 3.44.9 and 3.50.0: analysis, 76 tests per
version, Android arm64 Debug APK and iOS simulator Debug builds all passed. Final
Android configuration passed 105 JVM tests; repository checks passed 38 Python
regressions and the optional native fixture analysis. iOS 26.5 example runtime
passed on minimum/latest Flutter, including background interruption and disposal.
Physical screenshot/recording positives remain pending; no Android runtime rerun.
Flutter 3.50 builds require iOS 15+. Rolling stable CI is configured, not remotely
executed. See [compatibility evidence and device boundaries](flutter_compatibility.md).
No detection rules, fingerprint provider or backend were added.

## Native validation host layout (2026-11-14)

The internal test host now lives in `test_apps/native_validation/`; `example/`
remains the public API demo. Updated runner/check scripts and documentation;
kept application IDs, local SDK dependency depth and all 76 non-README source/
configuration files byte-identical. Regenerated build metadata at the new path.
The host README now describes implemented detectors instead of the obsolete stub.

Executed: 76 Dart/Flutter tests, 39 Python regressions, optional host analysis,
105 Android JVM tests, Android split-screen with the real companion APK, three
iOS Scene creation/destruction/engine-release cycles and actual iOS PiP start/stop.
All passed from the new location with validated fresh builds. Physical-device
acceptance remains separate. See [migration evidence](validation_runs/2026-11-14/native_validation_move.json).

## Developer settings (2026-11-14)

Added independent developerMode / usbDebugging public-setting observations on
Android. Only explicit 1 is positive; potentially redacted 0 stays unsupported,
and missing/invalid/read-failed values stay errors. iOS explicitly reports both
unsupported. Public enums append new values, existing detectors retain their rule
versions, and the portable example covers 16 IDs. No wireless-ADB probing or
third-party fingerprinting was added.

Executed: 81 Dart/Flutter, 43 Python, 119 Android JVM regressions, six iOS XCTests,
iOS 13 type checks, three controlled Android setting cases, iOS full demo and the
latest supported Flutter Android build. Android full-demo recording setup failed
and remains separately recorded, not counted as a pass. Physical devices pending.
See [developer-setting validation](developer_settings.md).
