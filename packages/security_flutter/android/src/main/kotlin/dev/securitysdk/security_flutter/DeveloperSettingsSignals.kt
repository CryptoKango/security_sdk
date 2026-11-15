package dev.securitysdk.security_flutter

import android.provider.Settings

/** Read only public settings. A zero may be platform-redacted for third-party apps. */
internal object DeveloperSettingsSignals {
    fun scan(id: String, read: (String) -> String?): LocalFinding {
        val (key, enabledReason) = when (id) {
            "developerMode" -> Settings.Global.DEVELOPMENT_SETTINGS_ENABLED to "developerModeEnabled"
            "usbDebugging" -> Settings.Global.ADB_ENABLED to "usbDebuggingEnabled"
            else -> return LocalFinding.unsupported("unimplemented")
        }
        return try {
            val raw = read(key)
            val finding = when (raw) {
                "1" -> LocalFinding.signal(true, enabledReason)
                // Public Android documentation allows a constant zero for third-party
                // callers. Do not claim disabled, infer from the other setting, or
                // use hidden wireless-ADB keys / shell / app debuggable flags.
                "0" -> LocalFinding.unsupported("settingReadRestricted")
                else -> LocalFinding.error("settingValueUnavailable")
            }
            finding.withValues(mapOf("settingValue" to (if (raw == "0" || raw == "1") raw.toInt() else null),
                "settingPresent" to (raw != null), "settingValueValid" to (raw == "0" || raw == "1")))
        } catch (_: SecurityException) {
            LocalFinding.error("missingPermission")
        } catch (_: Exception) {
            LocalFinding.error("nativeFailure")
        }
    }
}
