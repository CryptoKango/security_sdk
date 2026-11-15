package dev.securitysdk.security_flutter

/** Public APIs describe the current profile, not a universal OEM clone detector. */
internal object ProfilePolicy {
    fun scan(sdk: Int, managed: () -> Boolean, profile: () -> Boolean,
             userType: () -> String? = { null }): LocalFinding {
        // isManagedProfile became public in API 30. Do not call hidden versions.
        if (sdk < 30) return LocalFinding.unsupported("profileTypeUnavailable")
        if (managed()) return LocalFinding.signal(true, "managedProfile")
        if (sdk < 33) return LocalFinding.unsupported("profileTypeUnavailable")
        if (!profile()) return LocalFinding.signal(false, "managedProfile")
        // LauncherUserInfo is public from API 35. Read only the calling user;
        // private, unknown and inaccessible profiles must not become clone or clean.
        if (sdk >= 35 && userType() == "android.os.usertype.profile.CLONE") {
            return LocalFinding.signal(true, "cloneProfile")
        }
        return LocalFinding.unsupported("profileTypeUnavailable")
    }
}
