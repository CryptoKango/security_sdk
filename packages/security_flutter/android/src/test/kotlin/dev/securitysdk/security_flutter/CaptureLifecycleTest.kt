package dev.securitysdk.security_flutter

import android.app.Activity
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import org.junit.Assert.*
import org.junit.*
import org.junit.runner.RunWith
import org.robolectric.*
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy
import java.util.concurrent.*

/** Actual plugin callbacks, fake OS capture endpoints. Not a real FlutterEngine. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34, 35])
@android.annotation.SuppressLint("NewApi") // Framework fixtures run only API 34/35.
class CaptureLifecycleTest {
    class CaptureActivity : Activity() {
        var focused = true
        var pip = false
        var multiWindow = false
        override fun isInPictureInPictureMode() = pip
        override fun isInMultiWindowMode() = multiWindow
        var failedRemovals = 0
        val callbacks = mutableSetOf<ScreenCaptureCallback>()
        val callbackExecutors = mutableMapOf<ScreenCaptureCallback, Executor>()
        override fun hasWindowFocus() = focused
        override fun registerScreenCaptureCallback(executor: Executor, callback: ScreenCaptureCallback) { callbacks.add(callback); callbackExecutors[callback] = executor }
        override fun unregisterScreenCaptureCallback(callback: ScreenCaptureCallback) {
            if (failedRemovals-- > 0) throw IllegalStateException("fixture cleanup")
            callbacks.remove(callback)
            callbackExecutors.remove(callback)
        }
        var recordingAdds = 0
        var recordingState = WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE
        var failRecordingRemovals = 0
        val recordingCallbacks = mutableSetOf<Any>()
        private val manager = Proxy.newProxyInstance(WindowManager::class.java.classLoader, arrayOf(WindowManager::class.java)) { _, method, args ->
            when (method.name) {
                "addScreenRecordingCallback" -> { recordingAdds++; recordingCallbacks.add(args!![1]); recordingState }
                "removeScreenRecordingCallback" -> {
                    if (failRecordingRemovals-- > 0) throw IllegalStateException("fixture cleanup")
                    recordingCallbacks.remove(args!![0]); null
                }
                else -> null
            }
        } as WindowManager
        override fun getWindowManager(): WindowManager = manager
    }
    private class Binding(val activity: CaptureActivity) {
        val listeners = mutableSetOf<PluginRegistry.WindowFocusChangedListener>()
        val value = Proxy.newProxyInstance(ActivityPluginBinding::class.java.classLoader, arrayOf(ActivityPluginBinding::class.java)) { _, method, args ->
            when (method.name) {
                "getActivity" -> activity
                "addOnWindowFocusChangedListener" -> { listeners.add(args!![0] as PluginRegistry.WindowFocusChangedListener); null }
                "removeOnWindowFocusChangedListener" -> { listeners.remove(args!![0]); null }
                else -> null
            }
        } as ActivityPluginBinding
        fun focus(value: Boolean) { activity.focused = value; listeners.toList().forEach { it.onWindowFocusChanged(value) } }
    }
    private class Reply : MethodChannel.Result {
        var value: Map<*, *>? = null
        var error: String? = null
        override fun success(result: Any?) { value = result as Map<*, *> }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() { error = "unimplemented" }
        fun finding() = (value!!["findings"] as List<*>).last() as Map<*, *>
    }
    private val plugins = mutableListOf<SecurityFlutterPlugin>()
    private val activities = mutableListOf<CaptureActivity>()
    @Before fun permissions() { shadowOf(RuntimeEnvironment.getApplication()).grantPermissions("android.permission.DETECT_SCREEN_CAPTURE", "android.permission.DETECT_SCREEN_RECORDING") }
    @After fun cleanup() { plugins.forEach { it.detachEngineResources() }; activities.forEach { it.finish() } }
    private fun activity() = Robolectric.buildActivity(CaptureActivity::class.java).setup().get().also { activities.add(it) }
    private fun field(plugin: SecurityFlutterPlugin, name: String, value: Any) {
        SecurityFlutterPlugin::class.java.getDeclaredField(name).apply { isAccessible = true }.set(plugin,value)
    }
    private fun plugin(binding: Binding) = SecurityFlutterPlugin().also {
        field(it,"context",RuntimeEnvironment.getApplication()); it.onAttachedToActivity(binding.value); plugins.add(it)
    }
    private fun call(plugin: SecurityFlutterPlugin, method: String, ids: List<String> = listOf("screenshot")): Reply {
        val reply = Reply()
        plugin.onMethodCall(MethodCall(method,mapOf("owner" to "same-owner", "contextId" to "test", "detectorIds" to ids)),reply)
        return reply
    }
    private fun scan(plugin: SecurityFlutterPlugin) = call(plugin,"scan").finding()
    @Test fun destroyedActivityReleasesBindingEvenIfHostDefersEngineDetach() {
        val binding=Binding(activity()); val plugin=plugin(binding)
        call(plugin,"startScreenshotObservation")
        val old=binding.activity.callbacks.single();old.onScreenCaptured()
        plugin.onActivityDestroyed(binding.activity)
        assertTrue(binding.listeners.isEmpty())
        for(name in listOf("activity","activityBinding","observedDecor","focusTree")) {
            val value=plugin.javaClass.getDeclaredField(name).also { it.isAccessible=true }.get(plugin)
            assertNull(name,value)
        }
        assertTrue(binding.activity.callbacks.isEmpty())
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        val next=Binding(activity());plugin.onAttachedToActivity(next.value)
        call(plugin,"startScreenshotObservation");old.onScreenCaptured()
        plugin.onActivityDestroyed(binding.activity) // Late old callback cannot detach the new host.
        assertEquals("notDetected",scan(plugin)["status"])
        assertEquals(1,next.listeners.size)
    }
    @Test fun memoryPressureAloneDoesNotInventCaptureOrClearHistory() {
        val binding=Binding(activity());val plugin=plugin(binding)
        call(plugin,"startScreenshotObservation")
        for(level in listOf(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
                android.content.ComponentCallbacks2.TRIM_MEMORY_BACKGROUND,android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE)) {
            binding.activity.onTrimMemory(level)
            assertEquals("notDetected",scan(plugin)["status"])
        }
        binding.activity.callbacks.single().onScreenCaptured()
        binding.activity.onLowMemory()
        assertEquals("screenshotObserved",scan(plugin)["reason"])
        plugin.onActivityStopped(binding.activity)
        binding.activity.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        plugin.onActivityResumed(binding.activity)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
    }
    @Test fun identicalOwnersAcrossTwoBindingsAreIsolated() {
        val activity=activity(); val ab=Binding(activity); val bb=Binding(activity); val a=plugin(ab); val b=plugin(bb)
        assertNull(call(a,"startScreenshotObservation").error); assertNull(call(b,"startScreenshotObservation").error)
        assertEquals(2,activity.callbacks.size); val old=activity.callbacks.first()
        call(a,"stopScreenshotObservation"); old.onScreenCaptured()
        assertEquals("noKnownSignal",scan(b)["reason"])
        activity.callbacks.single().onScreenCaptured()
        a.detachEngineResources()
        assertTrue(ab.listeners.isEmpty()); assertEquals(1,bb.listeners.size)
        assertEquals(1,activity.callbacks.size); assertEquals("screenshotObserved",scan(b)["reason"])
    }
    @Test fun screenshotCallbackQueuedBeforeFocusLossCannotContaminateRestart() {
        val activity = activity(); val binding = Binding(activity); val plugin = plugin(binding)
        call(plugin, "startScreenshotObservation")
        val callback = activity.callbacks.single()
        activity.callbackExecutors.getValue(callback).execute { callback.onScreenCaptured() }
        binding.focus(false); binding.focus(true)
        assertEquals("observationInterrupted", scan(plugin)["reason"])
        assertEquals(mapOf("screenshotObserved" to false, "observationActive" to false), scan(plugin)["values"])
        call(plugin, "startScreenshotObservation")
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("noKnownSignal", scan(plugin)["reason"])
        activity.callbacks.single().onScreenCaptured()
        assertEquals("screenshotObserved", scan(plugin)["reason"])
    }
    @Test fun screenshotThenSystemOverlayPreservesUnknownUntilExplicitRestart() {
        val activity = activity(); val binding = Binding(activity); val plugin = plugin(binding)
        call(plugin, "startScreenshotObservation")
        activity.callbacks.single().onScreenCaptured()
        assertEquals("screenshotObserved", scan(plugin)["reason"])
        binding.focus(false); binding.focus(true)
        val interrupted = scan(plugin)
        assertEquals("observationInterrupted", interrupted["reason"])
        assertEquals("error", interrupted["status"])
        assertEquals(mapOf("screenshotObserved" to true, "observationActive" to false), interrupted["values"])
        call(plugin, "startScreenshotObservation")
        assertEquals("noKnownSignal", scan(plugin)["reason"])
        assertEquals(mapOf("signalDetected" to false, "screenshotObserved" to false, "observationActive" to true), scan(plugin)["values"])
        call(plugin, "stopScreenshotObservation")
        assertEquals("observationRequired", scan(plugin)["reason"])
        assertNull(scan(plugin)["values"])
    }
    @Test fun pauseWithRetainedFocusCannotStartAndOldCallbackCannotAffectRestart() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        val old=activity.callbacks.single(); plugin.onActivityPaused(activity)
        assertTrue(activity.hasWindowFocus())
        assertEquals("platform_unavailable",call(plugin,"startScreenshotObservation").error)
        assertTrue(activity.callbacks.isEmpty())
        plugin.onActivityResumed(activity); call(plugin,"startScreenshotObservation"); old.onScreenCaptured()
        assertEquals("noKnownSignal",scan(plugin)["reason"])
    }
    @Test fun focusGapIsTerminalUntilExplicitStart() {
        val binding=Binding(activity()); val plugin=plugin(binding); call(plugin,"startScreenshotObservation")
        binding.focus(false); binding.focus(true)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        call(plugin,"startScreenshotObservation"); assertEquals("noKnownSignal",scan(plugin)["reason"])
    }
    @Test fun decorFocusLossWorksWithoutFlutterForwardingAndDetachRemovesItsListener() {
        val activity=activity(); val binding=Binding(activity); val plugin=plugin(binding)
        call(plugin,"startScreenshotObservation")
        val tree=activity.window.decorView.viewTreeObserver
        val dispatch=tree.javaClass.getDeclaredMethod("dispatchOnWindowFocusChange",Boolean::class.javaPrimitiveType)
        dispatch.isAccessible=true
        dispatch.invoke(tree,false); dispatch.invoke(tree,true)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        call(plugin,"startScreenshotObservation"); assertEquals("noKnownSignal",scan(plugin)["reason"])
        plugin.onDetachedFromActivity()
        val epoch=plugin.javaClass.getDeclaredField("captureEpoch").also { it.isAccessible=true }
        val before=epoch.getLong(plugin)
        dispatch.invoke(tree,false)
        assertEquals(before,epoch.getLong(plugin))
        plugin.onAttachedToActivity(binding.value)
        val reattached=epoch.getLong(plugin)
        dispatch.invoke(tree,false)
        assertEquals(reattached+1,epoch.getLong(plugin)) // A leaked old listener would fire twice.
    }
    @Test fun rebindingWithoutDetachReleasesOldViewAndIgnoresItsCallbacks() {
        val old=Binding(activity()); val plugin=plugin(old); call(plugin,"startScreenshotObservation")
        val callback=old.activity.callbacks.single(); val focus=old.listeners.single(); val next=Binding(activity())
        plugin.onAttachedToActivity(next.value)
        assertTrue(old.activity.callbacks.isEmpty()); assertTrue(old.listeners.isEmpty())
        call(plugin,"startScreenshotObservation"); callback.onScreenCaptured(); focus.onWindowFocusChanged(false)
        plugin.onActivityPaused(old.activity)
        assertEquals("noKnownSignal",scan(plugin)["reason"]); assertEquals(1,next.activity.callbacks.size)
    }
    @Test fun stopFailureInvalidatesAndRetainsCleanupForRetry() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        val callback=activity.callbacks.single(); activity.failedRemovals=1
        assertEquals("platform_unavailable",call(plugin,"stopScreenshotObservation").error)
        callback.onScreenCaptured(); assertEquals("observationInterrupted",scan(plugin)["reason"])
        assertNull(call(plugin,"stopScreenshotObservation").error)
        assertTrue(activity.callbacks.isEmpty()); assertEquals("observationRequired",scan(plugin)["reason"])
    }
    @Test fun failedPauseRemovalIsRetriedBeforeReplacement() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.failedRemovals=1; plugin.onActivityPaused(activity); assertEquals(1,activity.callbacks.size)
        plugin.onActivityResumed(activity); call(plugin,"startScreenshotObservation")
        assertEquals(1,activity.callbacks.size); assertEquals("noKnownSignal",scan(plugin)["reason"])
    }
    @Test @Config(sdk=[35]) fun recordingCleanupFailureCannotBeCleanOrAccumulateListeners() {
        val activity=activity(); val plugin=plugin(Binding(activity))
        fun recording()=call(plugin,"scan",listOf("screenRecording")).finding()
        assertEquals("notDetected",recording()["status"]); assertTrue(activity.recordingCallbacks.isEmpty())
        activity.failRecordingRemovals=2; assertEquals("error",recording()["status"])
        assertEquals(1,activity.recordingCallbacks.size); val adds=activity.recordingAdds
        assertEquals("error",recording()["status"]); assertEquals(adds,activity.recordingAdds)
        assertEquals("notDetected",recording()["status"]); assertTrue(activity.recordingCallbacks.isEmpty())
        plugin.onActivityPaused(activity); assertEquals("noActivity",recording()["reason"])
    }
    @Test @Config(sdk=[35]) fun recordingIsFreshAcrossResizeFocusAndConfigurationReattachment() {
        val first=Binding(activity()); val plugin=plugin(first)
        fun recording()=call(plugin,"scan",listOf("screenRecording")).finding()
        repeat(3) {
            first.activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            assertEquals("detected",recording()["status"])
            assertTrue(first.activity.recordingCallbacks.isEmpty())
            first.activity.multiWindow=true
            first.focus(false)
            val adds=first.activity.recordingAdds
            assertEquals("noActivity",recording()["reason"])
            assertEquals(adds,first.activity.recordingAdds)
            first.activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE
            first.focus(true)
            assertEquals("notDetected",recording()["status"])
            assertTrue(first.activity.recordingCallbacks.isEmpty())
        }
        plugin.onDetachedFromActivityForConfigChanges()
        assertEquals("noActivity",recording()["reason"])
        val next=Binding(activity())
        next.activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_VISIBLE
        plugin.onReattachedToActivityForConfigChanges(next.value)
        assertEquals("detected",recording()["status"])
        assertTrue(next.activity.recordingCallbacks.isEmpty())
        assertTrue(first.activity.recordingCallbacks.isEmpty())
    }
    @Test fun repeatedFoldLikeDetachCannotInventOrTransferScreenshotHistory() {
        var current=Binding(activity()); val plugin=plugin(current)
        repeat(3) { cycle ->
            call(plugin,"startScreenshotObservation")
            val old=current.activity.callbacks.single()
            if(cycle==0) old.onScreenCaptured()
            plugin.onActivityPaused(current.activity)
            plugin.onDetachedFromActivityForConfigChanges()
            val next=Binding(activity())
            plugin.onReattachedToActivityForConfigChanges(next.value)
            val interrupted=scan(plugin)
            assertEquals("observationInterrupted",interrupted["reason"])
            assertEquals(mapOf("screenshotObserved" to (cycle==0), "observationActive" to false),interrupted["values"])
            assertTrue(current.activity.callbacks.isEmpty())
            call(plugin,"stopScreenshotObservation")
            assertEquals("observationRequired",scan(plugin)["reason"])
            call(plugin,"startScreenshotObservation")
            old.onScreenCaptured()
            assertEquals("notDetected",scan(plugin)["status"])
            assertEquals(mapOf("signalDetected" to false,"screenshotObserved" to false,"observationActive" to true),scan(plugin)["values"])
            current=next
        }
    }
    @Test fun rotationAndFocusedSplitResizeKeepExistingScreenshotEvidence() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.callbacks.single().onScreenCaptured()
        activity.multiWindow=true
        val config=android.content.res.Configuration(activity.resources.configuration)
        config.orientation=android.content.res.Configuration.ORIENTATION_LANDSCAPE
        config.screenWidthDp=480
        activity.onConfigurationChanged(config)
        activity.window.decorView.layout(0,0,480,700)
        assertEquals("screenshotObserved",scan(plugin)["reason"])
        assertNull(call(plugin,"startScreenshotObservation").error)
        assertEquals(1,activity.callbacks.size)
        assertEquals("screenshotObserved",scan(plugin)["reason"])
    }
    @Test fun configurationDetachRequiresRestartAndDoesNotInheritOldCapture() {
        val old=Binding(activity()); val plugin=plugin(old); call(plugin,"startScreenshotObservation")
        val callback=old.activity.callbacks.single(); callback.onScreenCaptured()
        plugin.onDetachedFromActivityForConfigChanges()
        val next=Binding(activity()); plugin.onReattachedToActivityForConfigChanges(next.value)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        assertTrue(old.activity.callbacks.isEmpty())
        call(plugin,"startScreenshotObservation"); callback.onScreenCaptured()
        assertEquals("noKnownSignal",scan(plugin)["reason"])
    }
    @Test fun visiblePausedSplitWindowIsUnknownNotCleanOrMalicious() {
        val activity=activity(); activity.multiWindow=true
        val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        plugin.onActivityPaused(activity)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        assertEquals("platform_unavailable",call(plugin,"startScreenshotObservation").error)
        plugin.onActivityResumed(activity)
        // The failed explicit restart already released its prior interrupted owner.
        assertEquals("observationRequired",scan(plugin)["reason"])
        call(plugin,"startScreenshotObservation"); assertEquals("notDetected",scan(plugin)["status"])
    }
    @Test fun pipWithStaleFocusStillRejectsCaptureAndCannotResumeOldWindow() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.pip=true // Deliberately no pause or focus notification.
        assertTrue(activity.hasWindowFocus())
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        assertEquals("platform_unavailable",call(plugin,"startScreenshotObservation").error)
        activity.pip=false
        call(plugin,"startScreenshotObservation"); assertEquals("notDetected",scan(plugin)["status"])
    }
    @Test @Config(sdk=[35]) fun recordingRejectsPipAndInvalidatesScreenshotWindow() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.pip=true
        assertEquals("noActivity",call(plugin,"scan",listOf("screenRecording")).finding()["reason"])
        assertEquals(0,activity.recordingAdds)
        activity.pip=false
        assertEquals("observationInterrupted",scan(plugin)["reason"])
    }
    @Test fun decorDetachReattachInvalidatesAndReinstallsFocusObservation() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        val decor=activity.window.decorView
        // Dispatch through the listener installed on the actual decor. Android's
        // attach structures are framework-owned; this fixture supplies that boundary.
        val listenerField=plugin.javaClass.getDeclaredField("decorAttachListener").also { it.isAccessible=true }
        val listener=listenerField.get(plugin) as android.view.View.OnAttachStateChangeListener
        listener.onViewDetachedFromWindow(decor)
        assertEquals("platform_unavailable",call(plugin,"startScreenshotObservation").error)
        listener.onViewAttachedToWindow(decor)
        call(plugin,"startScreenshotObservation")
        val tree=decor.viewTreeObserver
        tree.javaClass.getDeclaredMethod("dispatchOnWindowFocusChange",Boolean::class.javaPrimitiveType)
          .also { it.isAccessible=true }.invoke(tree,false)
        assertEquals("observationInterrupted",scan(plugin)["reason"])
    }
    @Test fun asyncReplyObservingPipWithoutCallbacksPermanentlyInvalidatesOldWindow() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        val gate=CountDownLatch(1); val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
        executor.execute { try { gate.await() } catch (_: InterruptedException) {} }; field(plugin,"worker",executor)
        val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
        field(plugin,"channel",MethodChannel(messenger,"test"))
        val reply=call(plugin,"scan",listOf("appIntegrity","screenshot")); assertNull(reply.value)
        activity.pip=true // No lifecycle event: the reply-time prerequisite is the only evidence.
        gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS); shadowOf(Looper.getMainLooper()).idle()
        assertEquals("observationInterrupted",reply.finding()["reason"])
        activity.pip=false
        assertEquals("observationInterrupted",scan(plugin)["reason"])
        assertTrue(activity.callbacks.isEmpty())
    }
    @Test @Config(sdk=[35]) fun recordingInOneEngineCannotSupplyAHeadlessEngineWithAnActivity() {
        val binding=Binding(activity()); binding.activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_VISIBLE
        val foreground=plugin(binding)
        val headless=SecurityFlutterPlugin().also { field(it,"context",RuntimeEnvironment.getApplication()); plugins.add(it) }
        assertEquals("detected",call(foreground,"scan",listOf("screenRecording")).finding()["status"])
        assertEquals("noActivity",call(headless,"scan",listOf("screenRecording")).finding()["reason"])
        headless.detachEngineResources()
        assertEquals("detected",call(foreground,"scan",listOf("screenRecording")).finding()["status"])
        assertTrue(binding.activity.recordingCallbacks.isEmpty())
    }
    @Test @Config(sdk=[35]) fun permissionRevocationDuringMixedScanCannotReturnAPreviousRecordingPositive() {
        val activity=activity(); activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_VISIBLE
        val plugin=plugin(Binding(activity)); val gate=CountDownLatch(1)
        val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
        executor.execute { gate.await() }; field(plugin,"worker",executor)
        val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
        field(plugin,"channel",MethodChannel(messenger,"test"))
        val reply=call(plugin,"scan",listOf("appIntegrity","screenRecording"))
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions("android.permission.DETECT_SCREEN_RECORDING")
        gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS); shadowOf(Looper.getMainLooper()).idle()
        assertEquals("missingPermission",reply.finding()["reason"])
        assertEquals(0,activity.recordingAdds)
        assertTrue(activity.recordingCallbacks.isEmpty())
    }
    @Test @Config(sdk=[35]) fun mixedScanReadsRecordingAtReplyAfterScopeChangesWithoutFocusLoss() {
        val activity=activity(); val plugin=plugin(Binding(activity))
        for (initial in listOf(WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE, WindowManager.SCREEN_RECORDING_STATE_VISIBLE)) {
            activity.recordingState=initial
            val gate=CountDownLatch(1)
            val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
            executor.execute { gate.await() }; field(plugin,"worker",executor)
            val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
            field(plugin,"channel",MethodChannel(messenger,"test"))
            val reply=call(plugin,"scan",listOf("appIntegrity","screenRecording")); assertNull(reply.value)
            activity.recordingState=if(initial==WindowManager.SCREEN_RECORDING_STATE_VISIBLE)
                WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE else WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS); shadowOf(Looper.getMainLooper()).idle()
            assertEquals(if(activity.recordingState==WindowManager.SCREEN_RECORDING_STATE_VISIBLE) "detected" else "notDetected",reply.finding()["status"])
            assertTrue(activity.recordingCallbacks.isEmpty())
            executor.shutdownNow()
        }
    }
    @Test @Config(sdk=[35]) @org.robolectric.annotation.LooperMode(org.robolectric.annotation.LooperMode.Mode.PAUSED)
    fun mixedRecordingDoesNotReadReplacementActivityOrReplyAfterEngineDestruction() {
        for (destroyEngine in listOf(false,true)) {
            val old=Binding(activity()); val next=Binding(activity())
            next.activity.recordingState=WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            val plugin=plugin(old)
            val gate=CountDownLatch(1)
            val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
            executor.execute { gate.await() }; field(plugin,"worker",executor)
            val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
            field(plugin,"channel",MethodChannel(messenger,"test"))
            val reply=call(plugin,"scan",listOf("appIntegrity","screenRecording"))
            gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS)
            assertNull(reply.value) // No Activity.setup() here: it drains Robolectric main tasks.
            if(destroyEngine) plugin.detachEngineResources() else {
                plugin.onDetachedFromActivityForConfigChanges(); plugin.onReattachedToActivityForConfigChanges(next.value)
            }
            shadowOf(Looper.getMainLooper()).idle()
            if(destroyEngine) assertNull(reply.value) else assertEquals("observationInterrupted",reply.finding()["reason"])
            assertEquals(0,next.activity.recordingAdds)
            assertTrue(old.activity.recordingCallbacks.isEmpty())
            executor.shutdownNow()
        }
    }
    @Test fun mixedScanCannotCopyHistoricalScreenshotIntoReplacementWindow() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.callbacks.single().onScreenCaptured()
        val gate=CountDownLatch(1); val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
        executor.execute { try { gate.await() } catch (_: InterruptedException) {} }; field(plugin,"worker",executor)
        val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
        field(plugin,"channel",MethodChannel(messenger,"test"))
        val reply=call(plugin,"scan",listOf("appIntegrity","screenshot")); assertNull(reply.value)
        call(plugin,"stopScreenshotObservation"); call(plugin,"startScreenshotObservation")
        gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS); shadowOf(Looper.getMainLooper()).idle()
        assertEquals("observationInterrupted",reply.finding()["reason"])
        assertNull(reply.finding()["values"])
        assertEquals("noKnownSignal",scan(plugin)["reason"])
        assertEquals(mapOf("signalDetected" to false, "screenshotObserved" to false, "observationActive" to true), scan(plugin)["values"])
    }
    @Test fun mixedScanCannotDeliverCleanCaptureAcrossPauseResume() {
        val activity=activity(); val plugin=plugin(Binding(activity)); call(plugin,"startScreenshotObservation")
        activity.callbacks.single().onScreenCaptured()
        val gate=CountDownLatch(1); val executor=ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,LinkedBlockingQueue<Runnable>())
        executor.execute { try { gate.await() } catch (_: InterruptedException) {} }; field(plugin,"worker",executor)
        val messenger=Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,arrayOf(BinaryMessenger::class.java)) { _,_,_ -> null } as BinaryMessenger
        field(plugin,"channel",MethodChannel(messenger,"test"))
        val reply=call(plugin,"scan",listOf("appIntegrity","screenshot")); assertNull(reply.value)
        plugin.onActivityPaused(activity); plugin.onActivityResumed(activity)
        gate.countDown(); executor.submit {}.get(2,TimeUnit.SECONDS); shadowOf(Looper.getMainLooper()).idle()
        assertEquals("observationInterrupted",reply.finding()["reason"])
        assertEquals(mapOf("screenshotObserved" to true, "observationActive" to false), reply.finding()["values"])
    }
}
