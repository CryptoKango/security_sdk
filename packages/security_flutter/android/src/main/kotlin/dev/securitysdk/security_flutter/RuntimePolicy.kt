package dev.securitysdk.security_flutter

internal object RuntimePolicy {
    val ids = setOf("root", "hook", "debugger", "appIntegrity", "multiInstance")
    private val hashes = Regex("^[0-9a-fA-F]{64}$")
    private val modules = setOf("libfrida-gadget.so", "libfrida-agent.so", "libsubstrate.so",
        "libxposed_art.so", "libxposed.so", "liblsposed.so", "liblspd.so", "liblspatch.so", "libsandhook.so", "libepic.so")
    private val agentModules = setOf("frida-agent-32.so", "frida-agent-64.so",
        "frida-agent-arm.so", "frida-agent-arm64.so", "frida-agent.so")
    fun knownHookModule(path: String): Boolean =
        path.removeSuffix(" (deleted)").substringAfterLast('/').lowercase() in (modules + agentModules)
    private val zygiskPath = Regex("^/data/adb/modules/[^/]+/zygisk/[^/]+\\.so$")
    private fun hookReason(path: String): String? {
        val clean = path.removeSuffix(" (deleted)")
        if (clean.startsWith("/memfd:") && clean.removePrefix("/memfd:") in agentModules) return "hookMemfd"
        if (knownHookModule(clean)) return "hookModule"
        if (clean.split('/').none { it == "." || it == ".." } && zygiskPath.matches(clean)) return "injectedModulePath"
        return null
    }
    private val fieldsPattern = Regex("\\s+")
    private val addressPattern = Regex("[0-9a-fA-F]+-[0-9a-fA-F]+")
    private val permissionsPattern = Regex("[r-][w-][x-][ps]")
    private val hexPattern = Regex("[0-9a-fA-F]+")
    private val devicePattern = Regex("[0-9a-fA-F]+:[0-9a-fA-F]+")
    private val decimalPattern = Regex("[0-9]+")
    fun hookFinding(maps: String): LocalFinding {
        var entries = 0
        var reason: String? = null
        for (line in maps.lineSequence()) {
            if (line.isBlank()) continue
            // /proc/self/maps: address permissions offset device inode [path].
            val fields = line.trim().split(fieldsPattern, limit = 6)
            if (fields.size < 5) return LocalFinding.error("nativeFailure")
            val addresses = fields[0].split('-')
            val start = addresses.getOrNull(0)?.toULongOrNull(16)
            val end = addresses.getOrNull(1)?.toULongOrNull(16)
            if (!addressPattern.matches(fields[0]) || addresses.size != 2 || start == null || end == null || start >= end ||
                !permissionsPattern.matches(fields[1]) ||
                !hexPattern.matches(fields[2]) || fields[2].toULongOrNull(16) == null ||
                !devicePattern.matches(fields[3]) ||
                !decimalPattern.matches(fields[4]) || fields[4].toULongOrNull() == null) {
                return LocalFinding.error("nativeFailure")
            }
            if (++entries > 65536) return LocalFinding.error("scanLimitExceeded")
            // A module-shaped file mapped as data is not a loaded hook library.
            if (fields.size == 6 && fields[1][2] == 'x') {
                reason = reason ?: hookReason(fields[5])
            }
        }
        return if (entries == 0) LocalFinding.error("nativeFailure") else LocalFinding.signal(reason != null, reason ?: "hookModule")
    }
    fun tracerPid(status: String): Int? {
        val values = status.lineSequence().filter { it.startsWith("TracerPid:") }.toList()
        if (values.size != 1) return null
        val value = values.single().substringAfter(':').trim()
        return value.takeIf { decimalPattern.matches(it) }?.toIntOrNull()
    }
    fun signerSets(raw: Any?): List<Set<String>>? {
        val list = raw as? List<*> ?: return null
        if (list.isEmpty() || list.size > 8) return null
        val result = mutableListOf<Set<String>>()
        for (item in list) {
            val values = item as? List<*> ?: return null
            if (values.isEmpty() || values.size > 8 || values.any { it !is String || !hashes.matches(it) }) return null
            val set = values.map { (it as String).lowercase() }.toSet()
            if (set.size != values.size || set in result) return null
            result.add(set)
        }
        return result
    }
    fun signerFinding(actual: Set<String>, allowed: List<Set<String>>): LocalFinding = when {
        actual.isEmpty() -> LocalFinding.error("signingInfoUnavailable")
        actual in allowed -> LocalFinding("notDetected", "signingBaselineMatched")
        else -> LocalFinding.signal(true, "signingCertificateMismatch")
    }
}
