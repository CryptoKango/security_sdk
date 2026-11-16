package dev.securitysdk.security_flutter

import android.os.Build

/** Explicit basic descriptors only. Never reads names, serials or stable IDs. */
internal object DeviceInformation {
    fun collect(): Map<String, Any> = mapOf("schemaVersion" to 1, "device" to mapOf(
        "platform" to "android", "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND, "model" to Build.MODEL,
        "systemVersion" to Build.VERSION.RELEASE, "apiLevel" to Build.VERSION.SDK_INT))
}
