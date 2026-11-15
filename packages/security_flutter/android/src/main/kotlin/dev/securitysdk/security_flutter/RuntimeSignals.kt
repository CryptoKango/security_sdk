package dev.securitysdk.security_flutter

import android.content.Context
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.os.Process
import android.os.UserManager
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.security.MessageDigest

/** Read-only, bounded, per-request checks. Never executes su, attaches a debugger,
 * scans other processes, opens sockets, or enumerates installed applications. */
internal class RuntimeSignals(private val context: Context) {
    fun scan(id: String, policy: Any?): LocalFinding = try {
        when (id) {
            "root" -> root()
            "hook" -> hook()
            "multiInstance" -> multiInstance()
            "debugger" -> debugger()
            "appIntegrity" -> integrity(policy)
            else -> LocalFinding.unsupported("unimplemented")
        }
    } catch (_: ProbeLimitException) { LocalFinding.error("scanLimitExceeded")
    } catch (_: SecurityException) { LocalFinding.error("probeAccessRestricted")
    } catch (_: Exception) { LocalFinding.error("nativeFailure") }

    private fun root(): LocalFinding {
        if (Process.myUid() == 0) return LocalFinding.signal(true, "rootUid")
        var restricted = false
        for (path in listOf("/system/bin/su", "/system/xbin/su", "/system/bin/.ext/.su",
            "/sbin/su", "/vendor/bin/su", "/system/app/Superuser.apk", "/system/app/SuperSU.apk")) {
            try { Os.lstat(path); return LocalFinding.signal(true, "rootArtifact") }
            catch (error: ErrnoException) {
                when (error.errno) {
                    OsConstants.ENOENT, OsConstants.ENOTDIR -> Unit
                    OsConstants.EACCES, OsConstants.EPERM -> restricted = true
                    else -> return LocalFinding.error("nativeFailure")
                }
            }
        }
        val mounts = RootMountPolicy.finding(boundedText("/proc/self/mountinfo", 2 * 1024 * 1024))
        if (mounts.status != "notDetected") return mounts
        if (Build.TAGS?.split(',')?.any { it.trim() == "test-keys" } == true) {
            return LocalFinding.signal(true, "testKeysBuild")
        }
        return if (restricted) LocalFinding.error("probeAccessRestricted") else LocalFinding.signal(false, "rootArtifact")
    }

    private fun hook(): LocalFinding {
        for (name in listOf("de.robv.android.xposed.XposedBridge", "com.saurik.substrate.MS")) {
            try {
                Class.forName(name, false, context.classLoader)
                return LocalFinding.signal(true, "hookClass")
            } catch (_: ClassNotFoundException) { /* Not visible in this class loader. */
            } catch (_: LinkageError) { return LocalFinding.error("nativeFailure") }
        }
        val maps = boundedText("/proc/self/maps", 4 * 1024 * 1024)
        return RuntimePolicy.hookFinding(maps)
    }

    private fun debugger(): LocalFinding {
        val connected = Debug.isDebuggerConnected()
        if (connected) return LocalFinding.signal(true, "debuggerAttached")
            .withValues(mapOf("javaDebuggerConnected" to true))
        val waiting = Debug.waitingForDebugger()
        if (waiting) return LocalFinding.signal(true, "debuggerWaiting")
            .withValues(mapOf("javaDebuggerConnected" to false, "waitingForDebugger" to true))
        val pid = RuntimePolicy.tracerPid(boundedText("/proc/self/status", 64 * 1024))
            ?: return LocalFinding.error("nativeFailure")
        return LocalFinding.signal(pid != 0, "debuggerAttached").withValues(
            mapOf("javaDebuggerConnected" to false, "waitingForDebugger" to false, "processTraced" to (pid != 0)))
    }

    private fun multiInstance(): LocalFinding {
        val info = context.applicationInfo
        val uid = Os.getuid()
        // Isolated/SDK sandbox services are not normal application identities.
        if (!Process.isApplicationUid(uid)) return LocalFinding.unsupported("unsupportedProcess")
        var framework = false
        if (uid != info.uid) {
            for (name in listOf("com.lody.virtual.client.core.VirtualCore",
                "top.niunaijun.blackbox.BlackBoxCore")) {
                try { Class.forName(name, false, context.classLoader); framework = true; break }
                catch (_: ClassNotFoundException) { /* No initialization or installed-app enumeration. */ }
                catch (_: LinkageError) { return LocalFinding.error("nativeFailure") }
            }
        }
        val identity = ContainerPolicy.finding(context.packageName, info.dataDir, info.uid, uid, framework)
        if (identity.status != "notDetected") return identity
        return ProfilePolicy.scan(Build.VERSION.SDK_INT,
            managed = {
                if (Build.VERSION.SDK_INT < 30) throw IllegalStateException()
                val users = context.getSystemService(UserManager::class.java) ?: throw IllegalStateException()
                users.isManagedProfile
            },
            profile = {
                if (Build.VERSION.SDK_INT < 33) throw IllegalStateException()
                val users = context.getSystemService(UserManager::class.java) ?: throw IllegalStateException()
                users.isProfile
            },
            userType = {
                if (Build.VERSION.SDK_INT < 35) throw IllegalStateException()
                val launcher = context.getSystemService(LauncherApps::class.java) ?: throw IllegalStateException()
                launcher.getLauncherUserInfo(Process.myUserHandle())?.userType
            })
    }

    @Suppress("DEPRECATION")
    private fun integrity(raw: Any?): LocalFinding {
        if (raw == null) return LocalFinding.error("integrityBaselineRequired")
        val policy = raw as? Map<*, *> ?: return LocalFinding.error("integrityPolicyInvalid")
        val expected = policy["expectedApplicationId"] as? String
            ?: return LocalFinding.error("integrityPolicyInvalid")
        if (expected.length !in 1..255 || !Regex("^[A-Za-z0-9_.-]+$").matches(expected)) {
            return LocalFinding.error("integrityPolicyInvalid")
        }
        val rawSets = policy["androidSignerSha256Sets"]
        if (rawSets is List<*> && rawSets.isEmpty()) return LocalFinding.error("integrityBaselineRequired")
        val sets = RuntimePolicy.signerSets(rawSets) ?: return LocalFinding.error("integrityPolicyInvalid")
        if (context.packageName != expected) return LocalFinding.signal(true, "applicationIdMismatch")
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val info = context.packageManager.getPackageInfo(context.packageName, flags)
        // Deliberately compare current signers, not an ANY-match over historical
        // keys. Hosts explicitly include newly approved rotation sets.
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: return LocalFinding.error("signingInfoUnavailable")
            if (signing.hasMultipleSigners()) signing.apkContentsSigners
            else signing.signingCertificateHistory?.lastOrNull()?.let { arrayOf(it) }
        } else info.signatures
        if (signatures.isNullOrEmpty()) return LocalFinding.error("signingInfoUnavailable")
        val hashes = signatures.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        }.toSet()
        return RuntimePolicy.signerFinding(hashes, sets)
    }

    private fun boundedText(path: String, limit: Int): String = File(path).inputStream().use { input ->
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            val size = input.read(buffer)
            if (size < 0) break
            if (output.size() + size > limit) throw ProbeLimitException()
            output.write(buffer, 0, size)
        }
        output.toString(Charsets.UTF_8.name())
    }
    private class ProbeLimitException : Exception()
}
