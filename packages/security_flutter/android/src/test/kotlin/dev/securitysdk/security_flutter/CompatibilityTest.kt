package dev.securitysdk.security_flutter

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.location.Location
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.security.MessageDigest

/** Android framework JVM fixtures; not a device/FlutterEngine efficacy test. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 28, 30, 31, 33, 34, 35])
class CompatibilityTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var code: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, message: String?, details: Any?) { code = errorCode }
        override fun notImplemented() { code = "notImplemented" }
    }
    private fun plugin(): SecurityFlutterPlugin = SecurityFlutterPlugin().also {
        // Attach only application context: no Flutter JNI/engine is started in JVM tests.
        SecurityFlutterPlugin::class.java.getDeclaredField("context").apply { isAccessible = true }.set(it, context)
    }
    private fun scan(id: String): Map<*, *> {
        val reply = Reply()
        plugin().onMethodCall(MethodCall("scan", mapOf("contextId" to "test", "owner" to "test", "detectorIds" to listOf(id))), reply)
        assertNull(reply.code)
        return ((reply.value as Map<*, *>)["findings"] as List<*>).single() as Map<*, *>
    }
    @Test fun captureAvailabilityUsesActualSdkBoundaries() {
        val reply = Reply()
        plugin().onMethodCall(MethodCall("capabilities", null), reply)
        val caps = (reply.value as Map<*, *>)["capabilities"] as List<*>
        fun supported(id: String) = (caps.single { (it as Map<*, *>)["id"] == id } as Map<*, *>)["supported"]
        assertEquals(Build.VERSION.SDK_INT >= 34, supported("screenshot"))
        assertEquals(Build.VERSION.SDK_INT >= 35, supported("screenRecording"))
        val screenshot = scan("screenshot")
        assertEquals(if (Build.VERSION.SDK_INT < 34) "unsupportedOsVersion" else "observationRequired", screenshot["reason"])
        if (Build.VERSION.SDK_INT < 34) {
            val start = Reply()
            plugin().onMethodCall(MethodCall("startScreenshotObservation", mapOf("owner" to "test")), start)
            assertEquals("unsupported", start.code)
        }
        val recording = scan("screenRecording")
        assertEquals(if (Build.VERSION.SDK_INT < 35) "unsupportedOsVersion" else "missingPermission", recording["reason"])
    }
    @Test fun developerSettingsUsePublicProviderAndRoundTripThroughPlugin() {
        val pairs = listOf("developerMode" to Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
            "usbDebugging" to Settings.Global.ADB_ENABLED)
        val reply = Reply()
        plugin().onMethodCall(MethodCall("capabilities", null), reply)
        val caps = (reply.value as Map<*, *>)["capabilities"] as List<*>
        for ((id, key) in pairs) {
            assertEquals(true, (caps.single { (it as Map<*, *>)["id"] == id } as Map<*, *>)["supported"])
            Settings.Global.putString(context.contentResolver, key, "1")
            val enabled = scan(id)
            assertEquals("detected", enabled["status"])
            assertEquals(if (id == "developerMode") "developerModeEnabled" else "usbDebuggingEnabled", enabled["reason"])
            assertEquals("local-v1", enabled["detectorVersion"])
            Settings.Global.putString(context.contentResolver, key, "0")
            assertEquals("settingReadRestricted", scan(id)["reason"])
            Settings.Global.putString(context.contentResolver, key, "invalid")
            assertEquals("settingValueUnavailable", scan(id)["reason"])
        }
    }
    @Test fun missingNetworkPermissionNeverBecomesNoActiveNetwork() {
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions("android.permission.ACCESS_NETWORK_STATE")
        val finding = scan("vpn")
        assertEquals("error", finding["status"])
        assertEquals("missingPermission", finding["reason"])
    }
    private fun fix(): Location = Location("test").apply {
        accuracy = 5f
        elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos().coerceAtLeast(1)
    }
    @Test fun validLocationUsesLegacyOrModernSourceWithoutCoordinates() {
        // Give elapsed realtime a positive value on every emulated framework SDK.
        SystemClock.sleep(10)
        val location = fix()
        val metadata = LocationRiskMetadata.fromLocation(location)
        assertEquals(setOf("isMocked", "ageMilliseconds"), metadata.keys)
        assertEquals(false, metadata["isMocked"])
        assertTrue((metadata["ageMilliseconds"] as Long) >= 0)
        val justBefore = fix().apply { elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos() - 1 }
        assertEquals(1L, LocationRiskMetadata.fromLocation(justBefore)["ageMilliseconds"])
        if (Build.VERSION.SDK_INT >= 31) location.isMock = true
        else {
            // Test fixture setter on old framework jars; production only uses public getters.
            Location::class.java.getDeclaredMethod("setIsFromMockProvider", Boolean::class.javaPrimitiveType)
                .invoke(location, true)
        }
        assertEquals(true, LocationRiskMetadata.fromLocation(location)["isMocked"])
    }
    @Test fun invalidLocationCannotBecomeCleanOrMockPositive() {
        SystemClock.sleep(10)
        val invalid = listOf(Location("test"), Location("test").apply { elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos() },
            fix().apply { accuracy = -1f }, fix().apply { accuracy = Float.NaN },
            fix().apply { accuracy = Float.POSITIVE_INFINITY },
            fix().apply { elapsedRealtimeNanos = 0 }, fix().apply { elapsedRealtimeNanos = Long.MAX_VALUE })
        invalid.forEach { location -> assertThrows(IllegalArgumentException::class.java) { LocationRiskMetadata.fromLocation(location) } }
    }
    @Test @Config(sdk = [24, 27])
    @Suppress("DEPRECATION")
    fun legacySignerBaselineComparesTheOsSelectedSignerSet() {
        val signature = Signature(byteArrayOf(1, 2, 3))
        val info = PackageInfo().apply { packageName = context.packageName; signatures = arrayOf(signature) }
        shadowOf(context.packageManager).installPackage(info)
        val hash = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun check(h: String) = RuntimeSignals(context).scan("appIntegrity", mapOf(
            "expectedApplicationId" to context.packageName, "androidSignerSha256Sets" to listOf(listOf(h))))
        assertEquals("signingBaselineMatched", check(hash).reason)
        assertEquals("signingCertificateMismatch", check("0".repeat(64)).reason)
        info.signatures = null
        shadowOf(context.packageManager).installPackage(info)
        assertEquals("signingInfoUnavailable", check(hash).reason)
    }
}
