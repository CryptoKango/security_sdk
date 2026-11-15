package dev.securitysdk.security_flutter

/** Evidence about this app's environment; never counts other app instances. */
internal object ContainerPolicy {
    private val packageName = Regex("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*")
    private val container = Regex(
        "^/(?:data/(?:user|user_de)/[0-9]+|data/data|mnt/expand/[^/]+/(?:user|user_de)/[0-9]+)/" +
        "([^/]+)/virtual/data/(?:user|user_de)/[0-9]+/([^/]+)$")

    fun knownGuestPath(path: String, guest: String): Boolean {
        if (path.split('/').any { it == "." || it == ".." }) return false
        val match = container.matchEntire(path) ?: return false
        val host = match.groupValues[1]
        return packageName.matches(host) && host != guest && match.groupValues[2] == guest
    }

    fun finding(app: String, dataDir: String?, appUid: Int, processUid: Int,
                frameworkVisible: Boolean): LocalFinding {
        if (!packageName.matches(app) || dataDir.isNullOrEmpty() || !dataDir.startsWith('/') ||
            appUid < 0 || processUid < 0) return LocalFinding.error("processIdentityUnavailable")
        if (knownGuestPath(dataDir, app)) return LocalFinding.signal(true, "virtualContainerPath")
        if (appUid != processUid) {
            // The framework marker corroborates an identity discrepancy. Neither
            // a nonzero user ID nor a class bundled in a normal app suffices.
            return if (frameworkVisible) LocalFinding.signal(true, "virtualContainerIdentity")
                else LocalFinding.error("processIdentityMismatch")
        }
        return LocalFinding.signal(false, "virtualContainerPath")
    }
}
