package dev.securitysdk.security_flutter

import org.junit.Assert.*
import org.junit.Test

class DeveloperSettingsSignalsTest {
    private fun settings(value: Int?, present: Boolean = true): Map<String, Any?> = mapOf(
        "settingValue" to value, "settingPresent" to present, "settingValueValid" to (value != null))
    private fun enabled(reason: String) = LocalFinding("detected", reason,
        settings(1) + mapOf("signalDetected" to true))
    private val ids = listOf("developerMode", "usbDebugging")
    @Test fun positiveSettingsAreIndependentAndUseOnlyPublicKeys() {
        val settings = mapOf("development_settings_enabled" to "1", "adb_enabled" to "0")
        val reads = mutableListOf<String>()
        val findings = ids.map { id -> DeveloperSettingsSignals.scan(id) { key -> reads.add(key); settings[key] } }
        assertEquals(listOf("development_settings_enabled", "adb_enabled"), reads)
        assertEquals(enabled("developerModeEnabled"), findings[0])
        assertEquals(LocalFinding("unsupported", "settingReadRestricted", settings(0)), findings[1])
        assertEquals(enabled("usbDebuggingEnabled"), DeveloperSettingsSignals.scan("usbDebugging") { "1" })
    }
    @Test fun zeroNeverClaimsDisabledEvenOnAnOlderOs() {
        ids.forEach { id ->
            assertEquals(LocalFinding("unsupported", "settingReadRestricted", settings(0)), DeveloperSettingsSignals.scan(id) { "0" })
        }
    }
    @Test fun absentAndNonCanonicalValuesAreNotCleanOrPositive() {
        for (id in ids) for (raw in listOf(null, "", "true", "01", " 1", "1\n", "2", "-1", "private-value")) {
            assertEquals(LocalFinding("error", "settingValueUnavailable", settings(null, raw != null)), DeveloperSettingsSignals.scan(id) { raw })
        }
    }
    @Test fun permissionAndProviderFailuresRemainUnknownWithoutRawErrors() {
        ids.forEach { id ->
            assertEquals(LocalFinding("error", "missingPermission"), DeveloperSettingsSignals.scan(id) { throw SecurityException("private") })
            assertEquals(LocalFinding("error", "nativeFailure"), DeveloperSettingsSignals.scan(id) { throw IllegalStateException("private") })
        }
    }
    @Test fun everyExplicitScanReadsFreshState() {
        var raw = "1"
        var reads = 0
        val read: (String) -> String? = { reads++; raw }
        assertEquals("detected", DeveloperSettingsSignals.scan("developerMode", read).status)
        raw = "0"
        assertEquals("unsupported", DeveloperSettingsSignals.scan("developerMode", read).status)
        assertEquals(2, reads)
    }
    @Test fun unrelatedOrWirelessIdsDoNotReadSettings() {
        for (id in listOf("debugger", "wirelessDebugging", "unknown")) {
            var reads = 0
            assertEquals("unsupported", DeveloperSettingsSignals.scan(id) { reads++; "1" }.status)
            assertEquals(0, reads)
        }
    }
    @Test fun wireHasOnlyClosedSignalFieldsAndOwnRuleVersion() {
        ids.forEach { id ->
            val wire = DeveloperSettingsSignals.scan(id) { "1" }.wire(id)
            assertEquals(setOf("detectorId", "detectorVersion", "status", "reason", "values"), wire.keys)
            assertEquals(id, wire["detectorId"])
            assertEquals("local-v1", wire["detectorVersion"])
        }
    }
}
