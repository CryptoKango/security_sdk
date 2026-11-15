package dev.securitysdk.security_flutter

import org.junit.Assert.*
import org.junit.Test

class EnvironmentSignalsTest {
    @Test fun wirePreservesMeasuredFalseAndNullWithoutFabricatingUnknownReadings() {
        val finding = LocalFinding.signal(false, "proxyConfigured")
            .withValues(mapOf("hostProxyConfigured" to false, "other" to null))
        assertEquals(mapOf("signalDetected" to false, "hostProxyConfigured" to false, "other" to null), finding.wire("proxy")["values"])
        assertFalse(LocalFinding.error("nativeFailure").wire("proxy").containsKey("values"))
        assertTrue(LocalFinding.unsupported("unsupportedPlatform").values.isEmpty())
    }
    @Test fun emulatorMarkersAreSpecificAndNotTestKeysAlone() {
        assertTrue(EmulatorHeuristics.matches("sdk_gphone64_arm64", "Google", "sdk_gphone64_arm64", "ranchu"))
        assertFalse(EmulatorHeuristics.matches("Phone", "Vendor", "phone", "qcom"))
    }
    @Test fun normalSecondaryUserStorageIsNotTreatedAsCloning() {
        assertFalse(ContainerPolicy.knownGuestPath("/data/user/10/example.app", "example.app"))
        assertFalse(ContainerPolicy.knownGuestPath("/data/user/0/com.virtual.app", "com.virtual.app"))
        assertTrue(ContainerPolicy.knownGuestPath("/data/user/0/host/virtual/data/user/0/app", "app"))
    }
    @Test fun errorsAndUnsupportedDoNotBecomeNegativeSignals() {
        assertEquals("error", LocalFinding.error("missingPermission").wire("vpn")["status"])
        assertEquals("unsupported", LocalFinding.unsupported("unsupportedOsVersion").wire("screenshot")["status"])
        assertEquals("noKnownSignal", LocalFinding.signal(false, "vpnTransport").reason)
    }
    @Test fun genericPhysicalBuildAndIncidentalNamesAreNotEmulators() {
        assertFalse(EmulatorHeuristics.matches("unknown", "unknown", "generic", "qcom"))
        assertFalse(EmulatorHeuristics.matches("Emulator Edition Phone", "Vendor", "phone_sdk_gphone_case", "vendor_ranchu_adapter"))
        assertTrue(EmulatorHeuristics.matches("Android SDK built for arm64", "Google", "emulator", "ranchu"))
        assertTrue(EmulatorHeuristics.matches("Phone", "Genymotion", "phone", "vbox86"))
    }
    @Test fun pausedScreenshotWindowCannotResumeAsCleanOrAcceptLateEvents() {
        val observation = ScreenshotObservation()
        assertEquals("notDetected", observation.finding(true).status)
        observation.interrupt()
        observation.record()
        assertEquals("observationInterrupted", observation.finding(true).reason)
        assertEquals("error", observation.finding(false).status)
        val fresh = ScreenshotObservation()
        assertEquals("noActivity", fresh.finding(false).reason)
        fresh.record()
        assertEquals("screenshotObserved", fresh.finding(true).reason)
        fresh.interrupt()
        assertEquals("observationInterrupted", fresh.finding(true).reason)
    }
}
