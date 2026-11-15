package dev.securitysdk.security_flutter

import android.location.Location
import android.os.Build
import android.os.SystemClock

/** Adapt an already authorized business fix. Never acquires location or permissions.
 * The host forwards only these two fields through its own location channel.
 * Re-check permission/consent at each scan and include bridge latency in age.
 * Missing/non-finite accuracy and invalid elapsed times throw IllegalArgumentException;
 * discard that sample instead of manufacturing a false mock flag.
 */
object LocationRiskMetadata {
    @Suppress("DEPRECATION")
    fun fromLocation(location: Location): Map<String, Any> {
        val now = SystemClock.elapsedRealtimeNanos()
        val observed = location.elapsedRealtimeNanos
        // A default/invalid Location must not manufacture a clean source signal.
        require(location.hasAccuracy() && location.accuracy.isFinite() && location.accuracy >= 0)
        require(observed > 0 && now >= observed)
        val ageNanos = now - observed
        // Round up so sub-millisecond age is not silently erased at the bridge.
        val ageMillis = ageNanos / 1_000_000L + if (ageNanos % 1_000_000L == 0L) 0L else 1L
        return mapOf(
            "isMocked" to (if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider),
            "ageMilliseconds" to ageMillis,
        )
    }
}
