package dev.securitysdk.security_flutter

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.Manifest
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager

internal data class LocalFinding(val status: String, val reason: String,
    val values: Map<String, Any?> = emptyMap()) {
    fun wire(id: String): Map<String, Any?> = mapOf("detectorId" to id, "detectorVersion" to
        (if (id == "developerMode" || id == "usbDebugging") "local-v1" else "local-v7"),
        "status" to status, "reason" to reason) +
        (if (values.isEmpty()) emptyMap() else mapOf("values" to values))
    fun withValues(extra: Map<String, Any?>) = copy(values = values + extra)
    companion object {
        fun signal(found: Boolean, reason: String) = LocalFinding(
            if (found) "detected" else "notDetected", if (found) reason else "noKnownSignal",
            mapOf("signalDetected" to found))
        fun error(reason: String) = LocalFinding("error", reason)
        fun unsupported(reason: String) = LocalFinding("unsupported", reason)
    }
}

/** Bounded public-API observations. No shell, package enumeration or identifiers. */
internal class EnvironmentSignals(private val context: Context) {
    fun scan(id: String): LocalFinding = when (id) {
        "emulator" -> LocalFinding.signal(EmulatorHeuristics.matches(
            Build.MODEL, Build.MANUFACTURER, Build.PRODUCT, Build.HARDWARE), "emulatorBuild")
        "developerMode", "usbDebugging" -> DeveloperSettingsSignals.scan(id) { key ->
            Settings.Global.getString(context.contentResolver, key)
        }
        "automation" -> {
            when {
                ActivityManager.isUserAMonkey() -> LocalFinding.signal(true, "monkey")
                Build.VERSION.SDK_INT >= 29 && ActivityManager.isRunningInUserTestHarness() ->
                    LocalFinding.signal(true, "testHarness")
                else -> {
                    val manager = context.getSystemService(AccessibilityManager::class.java)
                        ?: returnError()
                    val gestures = manager.getEnabledAccessibilityServiceList(
                        AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
                        it.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_PERFORM_GESTURES != 0
                    }
                    LocalFinding.signal(gestures, "gestureService")
                }
            }
        }
        "accessibility" -> {
            val manager = context.getSystemService(AccessibilityManager::class.java) ?: returnError()
            val enabled = manager.isEnabled
            LocalFinding.signal(enabled, "accessibilityEnabled").withValues(mapOf("accessibilityEnabled" to enabled))
        }
        "vpn" -> vpn()
        "proxy" -> {
            val manager = context.getSystemService(ConnectivityManager::class.java) ?: returnError()
            val proxy = manager.defaultProxy
            val host = proxy != null && !proxy.host.isNullOrEmpty() && proxy.port > 0
            val pac = proxy != null && proxy.pacFileUrl != Uri.EMPTY
            LocalFinding.signal(host || pac, "proxyConfigured").withValues(
                mapOf("hostProxyConfigured" to host, "pacProxyConfigured" to pac))
        }
        else -> LocalFinding.unsupported("unimplemented")
    }

    // Optional host permission is intentionally absent from the library manifest.
    // Check explicitly; the plugin boundary also handles revocation SecurityException.
    @android.annotation.SuppressLint("MissingPermission")
    private fun vpn(): LocalFinding {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) {
            return LocalFinding.error("missingPermission")
        }
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: returnError()
        val network = manager.activeNetwork ?: return LocalFinding("notDetected", "noActiveNetwork",
            mapOf("activeNetworkAvailable" to false))
        val capabilities = manager.getNetworkCapabilities(network) ?: returnError()
        val vpn = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        return LocalFinding.signal(vpn, "vpnTransport").withValues(
            mapOf("activeNetworkAvailable" to true, "vpnTransport" to vpn))
    }

    private fun returnError(): Nothing = throw IllegalStateException()
}

/** Transparent heuristics: notDetected only means these markers did not match. */
internal object EmulatorHeuristics {
    fun matches(model: String, manufacturer: String, product: String, hardware: String): Boolean {
        val m = model.lowercase(); val p = product.lowercase(); val h = hardware.lowercase()
        // Unknown/generic Build fields also occur on physical devices and GSI
        // builds. They are not sufficient evidence, even when combined.
        return m == "google_sdk" || m == "emulator" || m.startsWith("android sdk built for ") ||
            manufacturer.equals("Genymotion", ignoreCase = true) ||
            p.startsWith("sdk_gphone") || p == "sdk" || p == "google_sdk" ||
            h == "goldfish" || h == "ranchu"
    }
}

