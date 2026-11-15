package dev.securitysdk.security_flutter

/** Only the caller's mount namespace is inspected. No generic rw/tmpfs verdict. */
internal object RootMountPolicy {
    private val decimal = Regex("[0-9]+")
    private val device = Regex("[0-9]+:[0-9]+")
    private val whitespace = Regex("\\s+")
    private val frameworkRoots = listOf("/data/adb/modules", "/data/adb/magisk",
        "/data/adb/metamodule", "/data/adb/ksu", "/data/adb/ap", "/sbin/.magisk", "/debug_ramdisk/.magisk")

    private val partitions = listOf("/system", "/system_ext", "/vendor", "/product", "/odm", "/oem")

    fun finding(mountinfo: String): LocalFinding {
        var count = 0
        var dataMountCount = 0
        var found = false
        val dataRoots = mutableMapOf<String, MutableList<String>>()
        val roots = mutableListOf<Pair<String, String>>()
        for (line in mountinfo.lineSequence()) {
            if (line.isBlank()) continue
            val f = line.trim().split(whitespace)
            val split = f.indexOf("-")
            if (split < 6 || f.size != split + 4 ||
                !decimal.matches(f[0]) || !decimal.matches(f[1]) || !device.matches(f[2])) {
                return LocalFinding.error("nativeFailure")
            }
            val root = unescape(f[3]) ?: return LocalFinding.error("nativeFailure")
            val target = unescape(f[4]) ?: return LocalFinding.error("nativeFailure")
            val source = unescape(f[split + 2]) ?: return LocalFinding.error("nativeFailure")
            if (!root.startsWith('/') || !target.startsWith('/')) return LocalFinding.error("nativeFailure")
            count++
            if (count > 16384) return LocalFinding.error("scanLimitExceeded")
            roots.add(f[2] to root)
            if (target == "/data") {
                if (++dataMountCount > 32) return LocalFinding.error("scanLimitExceeded")
                dataRoots.getOrPut(f[2]) { mutableListOf() }.add(root.trimEnd('/'))
            }
            if (f[split + 1] == "overlay" && partitions.any { target == it || target.startsWith("$it/") }) {
                val overlay = overlayFinding(f[split + 3])
                if (overlay.status == "error") return overlay
                if (overlay.status == "detected" && target.split('/').none { it == "." || it == ".." }) found = true
            }
            // /data/adb itself exists on stock devices. Match framework-specific
            // path components, not arbitrary substrings, overlayfs or user IDs.
            if (listOf(root, target, source).any(::frameworkPath)) found = true
        }
        // mountinfo roots are relative to the filesystem, often /adb/modules
        // for a filesystem mounted at /data. Correlate device + /data mount root;
        // never treat an arbitrary /adb directory on a different filesystem as root.
        if (!found) found = roots.any { (device, root) ->
            dataRoots[device]?.any { base ->
                root.startsWith("$base/") && frameworkPath("/data/" + root.removePrefix("$base/"))
            } == true
        }
        return if (count == 0) LocalFinding.error("nativeFailure")
            else LocalFinding.signal(found, "rootMountArtifact")
    }

    /** Restrict option evidence to overlay backing directories for system partitions.
     * Split delimiters before decoding mountinfo escapes; never search opaque options.
     * Unsupported/ambiguous escapes are unknown, not a root verdict or a clean scan. */
    private fun overlayFinding(raw: String): LocalFinding {
        val options = raw.split(',', limit = 258)
        if (options.size > 256) return LocalFinding.error("scanLimitExceeded")
        var found = false
        val seen = mutableSetOf<String>()
        for (option in options) {
            val key = option.substringBefore('=')
            if (key !in setOf("lowerdir", "upperdir", "workdir")) continue
            if (!seen.add(key) || '=' !in option) return LocalFinding.error("nativeFailure")
            val value = option.substringAfter('=')
            // A double colon separates overlay data-only lower layers.
            if (key == "lowerdir" && "::" in value &&
                Regex("(?<!:):(?!:)").containsMatchIn(value.substringAfter("::"))) {
                return LocalFinding.error("nativeFailure")
            }
            val layers = if (key == "lowerdir") value.split(Regex("::?"), limit = 130) else listOf(value)
            if (layers.size > 128) return LocalFinding.error("scanLimitExceeded")
            for (layer in layers) {
                val path = unescape(layer, optionPath = true) ?: return LocalFinding.error("nativeFailure")
                if (!path.startsWith('/')) return LocalFinding.error("nativeFailure")
                if (frameworkPath(path)) found = true
            }
        }
        return LocalFinding.signal(found, "rootMountArtifact")
    }

    private fun frameworkPath(path: String): Boolean {
        if (path.split('/').any { it == "." || it == ".." }) return false
        return frameworkRoots.any { path == it || path.startsWith("$it/") }
    }

    private fun unescape(value: String, optionPath: Boolean = false): String? {
        val output = StringBuilder()
        var index = 0
        while (index < value.length) {
            if (value[index] != '\\') { output.append(value[index++]); continue }
            if (index + 4 > value.length) return null
            val decoded = when (value.substring(index, index + 4)) {
                "\\040" -> ' '; "\\011" -> '\t'; "\\012" -> '\n'; "\\134" -> '\\'
                "\\054" -> if (optionPath) ',' else return null
                "\\072" -> if (optionPath) ':' else return null
                else -> return null
            }
            output.append(decoded); index += 4
        }
        return output.toString()
    }
}
