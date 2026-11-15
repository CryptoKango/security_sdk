package dev.securitysdk.security_flutter

import org.junit.Assert.*
import org.junit.Test

class RuntimePolicyTest {
    private val a = "a".repeat(64)
    private val b = "b".repeat(64)
    @Test fun signerComparisonRequiresExactSetNotOverlap() {
        assertEquals("detected", RuntimePolicy.signerFinding(setOf(a,b), listOf(setOf(a))).status)
        assertEquals("detected", RuntimePolicy.signerFinding(setOf(a), listOf(setOf(a,b))).status)
        assertEquals("notDetected", RuntimePolicy.signerFinding(setOf(a,b), listOf(setOf(b,a))).status)
    }
    @Test fun missingActualSignaturesCannotPass() {
        assertEquals("error", RuntimePolicy.signerFinding(emptySet(), listOf(setOf(a))).status)
    }
    @Test fun rotationMustBeAnExplicitApprovedSet() {
        assertEquals("detected", RuntimePolicy.signerFinding(setOf(b), listOf(setOf(a))).status)
        assertEquals("notDetected", RuntimePolicy.signerFinding(setOf(b), listOf(setOf(a),setOf(b))).status)
    }
    @Test fun invalidNativeBaselinesAreRejected() {
        for (value in listOf(null, listOf<Any>(), listOf(listOf<Any>()), listOf(listOf("bad")),
            listOf(listOf(a,a.uppercase())), listOf(listOf(a,b),listOf(b,a)), "wrong")) {
            assertNull(RuntimePolicy.signerSets(value))
        }
        assertEquals(listOf(setOf(a)), RuntimePolicy.signerSets(listOf(listOf(a.uppercase()))))
    }
    @Test fun tracerPidParsingRejectsMissingMalformedAndDuplicates() {
        assertEquals(0, RuntimePolicy.tracerPid("Name: app\nTracerPid:\t0\n"))
        assertEquals(42, RuntimePolicy.tracerPid("TracerPid:\t42\n"))
        for (value in listOf("", "TracerPid: nope", "TracerPid: -1", "TracerPid: 0\nTracerPid: 1")) {
            assertNull(RuntimePolicy.tracerPid(value))
        }
    }
    @Test fun onlyKnownModuleBasenamesMatchNotApplicationNames() {
        assertEquals("detected", RuntimePolicy.hookFinding("1000-2000 r-xp 0000 00:00 1 /data/app/libfrida-gadget.so (deleted)").status)
        assertEquals("notDetected", RuntimePolicy.hookFinding("1000-2000 r-xp 0000 00:00 1 /data/app/com.frida.test/base.apk").status)
        assertFalse(RuntimePolicy.knownHookModule("/usr/lib/libfrida-gadget.so.backup"))
        assertFalse(RuntimePolicy.knownHookModule("/data/frida/libnormal.so"))
    }
    @Test fun malformedMapsNeverBecomeACompletedNegativeScan() {
        for (maps in listOf("", "unparseable", "1000-2000 nope 0 00:00 1 /lib.so",
            "2000-1000 r-xp 0 00:00 1 /lib.so", "1000-2000 r-xp 0 invalid 1 /lib.so",
            "1000-2000 r-xp 0 00:00 ? /lib.so", "1000-2000 rw-p 0 00:00 0\nbad line")) {
            assertEquals("error", RuntimePolicy.hookFinding(maps).status)
        }
        assertEquals("notDetected", RuntimePolicy.hookFinding("1000-2000 rw-p 0 00:00 0").status)
    }
    @Test fun mappingAFileAsDataIsNotLoadedExecutableHookCode() {
        assertEquals("notDetected", RuntimePolicy.hookFinding("1000-2000 r--p 0 00:00 1 /tmp/libfrida-gadget.so").status)
        assertEquals("detected", RuntimePolicy.hookFinding("1000-2000 r-xp 0 00:00 1 /tmp/libfrida-gadget.so").status)
        assertNull(RuntimePolicy.tracerPid("TracerPid: +1"))
    }
}
