package dev.securitysdk.security_flutter

import org.junit.Assert.*
import org.junit.Test

class HiddenEnvironmentTest {
    private fun mount(root: String = "/", target: String = "/", source: String = "/dev/block/dm-0",
                      device: String = "253:7", options: String = "rw") =
        "42 1 $device $root $target $options shared:1 - ext4 $source rw"
    private fun mapping(path: String, permissions: String = "r-xp") = "1000-2000 $permissions 0 00:01 1 $path"
    private fun container(uid: Int = 10123, process: Int = 10123, framework: Boolean = false,
                          path: String? = "/data/user/0/example.app") =
        ContainerPolicy.finding("example.app", path, uid, process, framework)

    @Test fun rootFrameworkMountsUseExactPathComponents() {
        for (path in listOf("/data/adb/modules/test/system/bin", "/sbin/.magisk/mirror", "/debug_ramdisk/.magisk/worker")) {
            assertEquals("rootMountArtifact", RootMountPolicy.finding(mount(root = path)).reason)
        }
        assertEquals("detected", RootMountPolicy.finding(mount(target = "/data/adb/ksu")).status)
        assertEquals("detected", RootMountPolicy.finding(mount(source = "/data/adb/modules/m/image")).status)
    }
    @Test fun stockWritableOverlayAndLookalikePathsAreNotRoot() {
        for (value in listOf(mount(target = "/data/adb"), mount(root = "/data/adb/modules_backup"),
            mount(root = "/data/user/0/example.app/files/data/adb/modules/test"),
            mount(target = "/system", source = "overlay"), mount(target = "/data", source = "tmpfs"),
            mount(options = "rw,context=magisk"))) {
            assertEquals("notDetected", RootMountPolicy.finding(value).status)
        }
    }
    @Test fun filesystemRelativeMountRootsRequireDataFilesystemCorrelation() {
        val module = mount(root = "/adb/modules/renamed/system", target = "/system")
        assertEquals("notDetected", RootMountPolicy.finding(module).status)
        assertEquals("detected", RootMountPolicy.finding(mount(target = "/data") + "\n" + module).status)
        assertEquals("notDetected", RootMountPolicy.finding(mount(target = "/data", device = "253:8") + "\n" + module).status)
    }
    @Test fun escapedMountPathsAndUnknownOptionalFieldsAreHandled() {
        assertEquals("detected", RootMountPolicy.finding(mount(root = "/data/adb/modules/a\\040b/system")).status)
        assertEquals("notDetected", RootMountPolicy.finding(mount(root = "/ordinary\\040folder").replace("shared:1", "future:tag")).status)
    }
    @Test fun malformedOrIncompleteMountDataIsUnknown() {
        for (value in listOf("", "broken", "1 0 0:1 / / rw", mount(root = "relative"),
            mount(root = "/bad\\999escape"), mount() + "\npartial")) {
            assertEquals("error", RootMountPolicy.finding(value).status)
        }
    }
    @Test fun exactKnownMemfdAgentsAndRenamedZygiskModulesAreObserved() {
        assertEquals("hookMemfd", RuntimePolicy.hookFinding(mapping("/memfd:frida-agent-64.so (deleted)")).reason)
        assertEquals("hookModule", RuntimePolicy.hookFinding(mapping("/data/local/tmp/frida-agent-arm64.so")).reason)
        assertEquals("injectedModulePath", RuntimePolicy.hookFinding(mapping("/data/adb/modules/arbitrary/zygisk/renamed.so")).reason)
    }
    @Test fun jitAnonymousDeletedAndIncidentalNamesAreNotHooks() {
        for (path in listOf("/memfd:jit-cache (deleted)", "[anon:dalvik-jit-code-cache]", "[anon:libc_malloc]",
            "/memfd:ordinary-agent (deleted)", "/memfd:frida-agent-64.so.backup (deleted)",
            "/data/user/0/example.app/data/adb/modules/test/zygisk/lib.so", "/data/adb/modules_backup/test/zygisk/lib.so")) {
            assertEquals("notDetected", RuntimePolicy.hookFinding(mapping(path)).status)
        }
        assertEquals("notDetected", RuntimePolicy.hookFinding(mapping("/memfd:frida-agent-64.so", "rw-p")).status)
    }
    @Test fun containerLayoutRequiresHostGuestBoundaryAndOwnPackage() {
        assertEquals("virtualContainerPath", container(path = "/data/user/10/host.app/virtual/data/user/0/example.app").reason)
        assertTrue(ContainerPolicy.knownGuestPath("/mnt/expand/volume/user_de/10/host.app/virtual/data/user/0/example.app", "example.app"))
        for (path in listOf("/data/user/0/example.app/virtual/data/user/0/example.app",
            "/data/user/0/host.app/virtual/data/user/0/other.app", "/data/user/0/example.app/files/virtual/",
            "/data/user/0/example.app/parallel/cache", "/data/user/0/host.app/virtual/data/user/0/../example.app")) {
            assertFalse(ContainerPolicy.knownGuestPath(path, "example.app"))
        }
    }
    @Test fun identityMismatchNeedsIndependentFrameworkEvidence() {
        assertEquals("virtualContainerIdentity", container(uid = 10200, framework = true).reason)
        assertEquals("detected", container(uid = 10200, framework = true).status)
        assertEquals("processIdentityMismatch", container(uid = 10200).reason)
        assertEquals("error", container(uid = 10200).status)
        assertEquals("notDetected", container(framework = true).status)
    }
    @Test fun secondaryUsersSharedUidsAndProfilesRetainTheirMeaning() {
        assertEquals("notDetected", container(uid = 1010123, process = 1010123, path = "/data/user/10/example.app").status)
        assertEquals("notDetected", container(uid = 10100, process = 10100).status)
        assertEquals("managedProfile", ProfilePolicy.scan(35, { true }, { true }).reason)
        assertEquals("notDetected", container(path = "/data/user_de/0/example.app").status)
    }
    @Test fun missingIdentityInputsAreErrorsNotCloneVerdicts() {
        assertEquals("error", container(path = null).status)
        assertEquals("processIdentityUnavailable", container(uid = -1).reason)
    }
    @Test fun mountEntryAndCorrelationBudgetsCannotReturnClean() {
        assertEquals("scanLimitExceeded", RootMountPolicy.finding(List(16385) { mount() }.joinToString("\n")).reason)
        assertEquals("scanLimitExceeded", RootMountPolicy.finding(List(33) { mount(target = "/data") }.joinToString("\n")).reason)
    }

    private fun overlay(options: String, target: String = "/system", source: String = "overlay") =
        "42 1 0:7 / $target ro - overlay $source $options"
    @Test fun systemOverlayBackingDirectoriesRevealFrameworkOrigins() {
        for (key in listOf("lowerdir", "upperdir", "workdir")) {
            for (target in listOf("/system", "/vendor/lib64", "/product", "/system_ext", "/odm", "/oem")) {
                assertEquals("rootMountArtifact", RootMountPolicy.finding(
                    overlay("ro,$key=/data/adb/modules/renamed/system", target, "KSU")).reason)
            }
        }
        for (layers in listOf("/system:/data/adb/modules/m/system", "/system::/data/adb/modules/m/system",
            "/data/adb/metamodule/upper", "/data/adb/modules/a\\040b/system")) {
            assertEquals("detected", RootMountPolicy.finding(overlay("lowerdir=$layers")).status)
        }
    }
    @Test fun genericOverlayLabelsAndOpaqueOptionsCannotCreateRootEvidence() {
        for (options in listOf("ro,lowerdir=/system,upperdir=/mnt/scratch/overlay/system/upper,workdir=/mnt/scratch/work",
            "lowerdir=/data/adb/modules_backup/m", "lowerdir=/data/user/0/app/files/data/adb/modules/m",
            "lowerdir=/ordinary\\072/data/adb/modules/m", "lowerdir=/ordinary\\054/data/adb/modules/m",
            "context=/data/adb/modules/m,lowerdir=/system", "lowerdir=/data/adb/modules/../ordinary")) {
            assertEquals(options, "notDetected", RootMountPolicy.finding(overlay(options, source = "KSU")).status)
        }
        assertEquals("notDetected", RootMountPolicy.finding(overlay("lowerdir=/data/adb/modules/m", "/system_backup")).status)
        assertEquals("notDetected", RootMountPolicy.finding(overlay("lowerdir=/data/adb/modules/m", "/data/local/tmp")).status)
        assertEquals("notDetected", RootMountPolicy.finding(mount(options = "lowerdir=/data/adb/modules/m")).status)
    }
    @Test fun ambiguousOrOversizedOptionsNeverMaskAnIncompleteScan() {
        for (options in listOf("lowerdir=", "lowerdir=relative", "lowerdir=/system:", "lowerdir=/system:::/other",
            "lowerdir=/data/adb/modules/m,lowerdir=/system", "lowerdir=/system::/data/adb/modules/m:/other", "lowerdir=/system\\999bad",
            "lowerdir=/data/adb/modules/m,upperdir=", "lowerdir=/ordinary\\:/data/adb/modules/m")) {
            assertEquals(options, "error", RootMountPolicy.finding(overlay(options)).status)
        }
        assertEquals("scanLimitExceeded", RootMountPolicy.finding(overlay(List(257) { "ro" }.joinToString(","))).reason)
        assertEquals("scanLimitExceeded", RootMountPolicy.finding(overlay("lowerdir=" + List(129) { "/system" }.joinToString(":"))).reason)
        assertEquals("error", RootMountPolicy.finding(overlay("lowerdir=/data/adb/modules/m") + "\npartial").status)
    }
    @Test fun lspatchRequiresAnExecutableExactModuleName() {
        for (path in listOf("/data/app/test/lib/arm64/liblspatch.so", "/data/local/tmp/liblspatch.so (deleted)")) {
            assertEquals("hookModule", RuntimePolicy.hookFinding(mapping(path)).reason)
            assertEquals("notDetected", RuntimePolicy.hookFinding(mapping(path, "r--p")).status)
        }
        for (path in listOf("/data/app/test/liblspatch.so.backup", "/data/app/liblspatch.so/ordinary.so",
            "/memfd:jit-cache (deleted)", "/data/app/ordinary/base.apk")) {
            assertEquals("notDetected", RuntimePolicy.hookFinding(mapping(path)).status)
        }
        assertEquals("error", RuntimePolicy.hookFinding(mapping("/data/local/tmp/liblspatch.so") + "\npartial").status)
        assertEquals("scanLimitExceeded", RuntimePolicy.hookFinding(List(65537) { mapping("/ordinary.so") }.joinToString("\n")).reason)
    }
}
