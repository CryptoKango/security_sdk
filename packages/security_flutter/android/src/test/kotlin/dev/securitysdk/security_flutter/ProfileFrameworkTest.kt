package dev.securitysdk.security_flutter

import android.content.Context
import android.content.pm.LauncherApps
import android.content.pm.LauncherUserInfo
import android.os.Build
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import android.system.Os
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowProcess
import org.robolectric.shadows.ShadowLauncherApps
import org.robolectric.shadows.ShadowUserManager
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

/** Controlled framework responses verify production wiring, not OEM efficacy. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 30, 33, 34, 35], shadows = [ProfileFrameworkTest.Identity::class, ProfileFrameworkTest.Users::class, ProfileFrameworkTest.Launcher::class])
class ProfileFrameworkTest {
    @Implements(Os::class)
    class Identity {
        companion object { @JvmStatic @Implementation fun getuid(): Int = Process.myUid() }
    }
    @Implements(UserManager::class)
    class Users : ShadowUserManager() {
        @Implementation(minSdk = 30) override fun isManagedProfile(): Boolean = managed
        @Implementation(minSdk = 33) override fun isProfile(): Boolean = profile
        companion object { var managed = false; var profile = true }
    }
    @Implements(LauncherApps::class)
    class Launcher : ShadowLauncherApps() {
        @Implementation(minSdk = 35)
        fun getLauncherUserInfo(user: UserHandle): LauncherUserInfo? {
            queried.add(user)
            if (denied) throw SecurityException("fixture")
            val type = userType ?: return null
            // Fixture creation only: production uses public APIs, never reflection.
            return ReflectionHelpers.callConstructor(LauncherUserInfo::class.java,
                ClassParameter.from(String::class.java, type),
                ClassParameter.from(Int::class.javaPrimitiveType, 0))
        }
        companion object {
            var userType: String? = "android.os.usertype.profile.CLONE"
            var denied = false
            val queried = mutableListOf<UserHandle>()
        }
    }
    private val context: Context get() = RuntimeEnvironment.getApplication()
    @Before fun prepare() {
        Users.managed = false; Users.profile = true
        Launcher.userType = "android.os.usertype.profile.CLONE"
        Launcher.denied = false; Launcher.queried.clear()
        // Robolectric's default Os.getuid reflects the JVM host, not an Android app.
        ShadowProcess.setUid(1010123)
        context.applicationInfo.uid = Os.getuid()
        assertTrue(Process.isApplicationUid(Os.getuid()))
    }
    private fun scan() = RuntimeSignals(context).scan("multiInstance", null)
    @Test fun onlyApi35QueriesTheCallingUser() {
        val result = scan()
        assertEquals(if (Build.VERSION.SDK_INT >= 35) "cloneProfile" else "profileTypeUnavailable", result.reason)
        assertEquals(if (Build.VERSION.SDK_INT >= 35) listOf(Process.myUserHandle()) else emptyList<UserHandle>(), Launcher.queried)
    }
    @Test @Config(sdk = [35]) fun unknownPrivateAndDeniedRemainUnknown() {
        for (type in listOf(null, "android.os.usertype.profile.PRIVATE", "vendor.CLONE")) {
            Launcher.userType = type
            assertEquals("unsupported", scan().status)
            assertEquals("profileTypeUnavailable", scan().reason)
        }
        Launcher.denied = true
        assertEquals("error", scan().status)
        assertEquals("probeAccessRestricted", scan().reason)
    }
    @Test @Config(sdk = [35]) fun ordinaryAndManagedProfilesSkipLauncherLookup() {
        Users.profile = false
        assertEquals("noKnownSignal", scan().reason)
        Users.managed = true
        assertEquals("managedProfile", scan().reason)
        assertTrue(Launcher.queried.isEmpty())
    }
}
