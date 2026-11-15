package dev.securitysdk.security_flutter

import org.junit.Assert.*
import org.junit.Test

class ProfilePolicyTest {
    @Test fun pre30NeverCallsNonPublicProfileMethods() {
        for (sdk in listOf(24, 28, 29)) {
            val result = ProfilePolicy.scan(sdk, { error("must not call") }, { error("must not call") })
            assertEquals("unsupported", result.status)
            assertEquals("profileTypeUnavailable", result.reason)
        }
    }
    @Test fun managedProfilesKeepSpecificNonMaliciousMeaning() {
        for (sdk in listOf(30, 32, 33, 36)) {
            assertEquals("managedProfile", ProfilePolicy.scan(sdk, { true }, { error("unneeded query") }).reason)
        }
    }
    @Test fun pre33FalseManagedFlagDoesNotProveNoCloneProfile() {
        for (sdk in listOf(30, 31, 32)) {
            assertEquals("unsupported", ProfilePolicy.scan(sdk, { false }, { error("unavailable") }).status)
        }
    }
    @Test fun inaccessibleProfilesRemainUnresolved() {
        assertEquals("profileTypeUnavailable", ProfilePolicy.scan(35, { false }, { true }).reason)
        assertEquals("unsupported", ProfilePolicy.scan(35, { false }, { true }).status)
    }
    @Test fun normalSecondaryUsersAreNotProfilesByNumericUidGuess() {
        assertEquals("notDetected", ProfilePolicy.scan(35, { false }, { false }).status)
        assertEquals("noKnownSignal", ProfilePolicy.scan(35, { false }, { false }).reason)
    }
    @Test fun profileQueryFailuresCannotFallBackToClean() {
        assertThrows(SecurityException::class.java) { ProfilePolicy.scan(35, { throw SecurityException() }, { false }) }
        assertThrows(IllegalStateException::class.java) { ProfilePolicy.scan(35, { false }, { throw IllegalStateException() }) }
    }
    @Test fun cloneTypeRequiresPublicApiAndExactSystemType() {
        for (sdk in listOf(35, 36)) {
            val result = ProfilePolicy.scan(sdk, { false }, { true }, { "android.os.usertype.profile.CLONE" })
            assertEquals("detected", result.status)
            assertEquals("cloneProfile", result.reason)
        }
        for (type in listOf(null, "", "android.os.usertype.profile.PRIVATE", "vendor.CLONE",
            "android.os.usertype.profile.CLONE.extra", "android.os.usertype.profile.clone")) {
            val result = ProfilePolicy.scan(35, { false }, { true }, { type })
            assertEquals("unsupported", result.status)
            assertEquals("profileTypeUnavailable", result.reason)
        }
    }
    @Test fun typeQueryIsNeverUsedBelow35OrOutsideNonManagedProfiles() {
        for (sdk in listOf(24, 29, 30, 32, 33, 34)) {
            ProfilePolicy.scan(sdk, { false }, { true }, { error("unavailable API") })
        }
        assertEquals("managedProfile", ProfilePolicy.scan(35, { true }, { error("unneeded") }, { error("unneeded") }).reason)
        assertEquals("notDetected", ProfilePolicy.scan(35, { false }, { false }, { error("unneeded") }).status)
    }
    @Test fun typeAccessFailurePropagatesInsteadOfClaimingCleanOrClone() {
        assertThrows(SecurityException::class.java) {
            ProfilePolicy.scan(35, { false }, { true }, { throw SecurityException() })
        }
    }
}
