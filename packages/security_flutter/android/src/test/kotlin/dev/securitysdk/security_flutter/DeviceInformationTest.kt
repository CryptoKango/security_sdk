package dev.securitysdk.security_flutter

import android.os.Build
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[24,35])
class DeviceInformationTest {
    @Test fun onlyNonUniqueDescriptorsAreReturnedWithoutAnActivityOrPermission() {
        val result=DeviceInformation.collect()
        assertEquals(setOf("schemaVersion","device"),result.keys)
        val device=result["device"] as Map<*,*>
        assertEquals(setOf("platform","manufacturer","brand","model","systemVersion","apiLevel"),device.keys)
        assertEquals("android",device["platform"])
        assertEquals(Build.MODEL,device["model"])
        assertEquals(Build.VERSION.SDK_INT,device["apiLevel"])
        assertEquals(Build.VERSION.RELEASE,device["systemVersion"])
    }
}
