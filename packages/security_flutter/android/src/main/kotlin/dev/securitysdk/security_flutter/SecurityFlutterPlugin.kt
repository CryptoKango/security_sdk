package dev.securitysdk.security_flutter

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import android.view.WindowManager
import android.view.View
import android.view.ViewTreeObserver
import java.lang.ref.WeakReference
import io.flutter.plugin.common.PluginRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.function.Consumer

/** Collection only in explicit calls. Observers are per owner and per engine. */
class SecurityFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, Application.ActivityLifecycleCallbacks {
    private var channel: MethodChannel? = null
    private var generation = 0
    private var worker: ThreadPoolExecutor? = null
    private val main = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var focusListener: PluginRegistry.WindowFocusChangedListener? = null
    private var focusTree: ViewTreeObserver? = null
    private var decorFocusListener: ViewTreeObserver.OnWindowFocusChangeListener? = null
    private var observedDecor: View? = null
    private var decorAttachListener: View.OnAttachStateChangeListener? = null
    private var decorDetached = false
    private var paused = false
    private var captureEpoch = 0L
    private var recordingCleanup: (() -> Unit)? = null
    private val observations = mutableMapOf<String, ScreenshotWindow>()
    private val detectorIds = listOf("root", "hook", "debugger", "appIntegrity",
        "emulator", "multiInstance", "automation", "developerMode", "usbDebugging", "accessibility", "vpn", "proxy",
        "screenshot", "screenRecording")

    private class ScreenshotWindow(current: Activity) {
        val state = ScreenshotObservation()
        val activity = WeakReference(current)
        val window = WeakReference(current.window)
        val decor = WeakReference(current.window.decorView)
        var release: (() -> Unit)? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        generation++
        worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(8))
        channel = MethodChannel(binding.binaryMessenger, "security_sdk/local/v1").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "deviceInfo" -> result.success(DeviceInformation.collect())
                "capabilities" -> result.success(mapOf("schemaVersion" to 1,
                    "capabilities" to detectorIds.map { mapOf("id" to it, "supported" to supported(it)) }))
                "scan" -> scan(call, result)
                "startScreenshotObservation", "stopScreenshotObservation" -> {
                    val owner = (call.arguments as? Map<*, *>)?.get("owner") as? String
                    if (owner.isNullOrEmpty() || owner.length > 128) {
                        result.error("invalid_request", "Invalid owner", null); return
                    }
                    if (call.method == "stopScreenshotObservation") {
                        release(owner)
                    } else {
                        if (Build.VERSION.SDK_INT < 34) {
                            result.error("unsupported", "Unsupported OS version", null); return
                        }
                        startScreenshot(owner)
                    }
                    result.success(mapOf("schemaVersion" to 1))
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("platform_unavailable", "Operation unavailable", null)
        }
    }

    private fun supported(id: String) = when (id) {
        "screenshot" -> Build.VERSION.SDK_INT >= 34
        "screenRecording" -> Build.VERSION.SDK_INT >= 35
        else -> true
    }

    private fun scan(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val contextId = args?.get("contextId") as? String
        val owner = args?.get("owner") as? String
        val ids = args?.get("detectorIds") as? List<*>
        if (contextId.isNullOrEmpty() || owner.isNullOrEmpty() || ids.isNullOrEmpty() ||
            ids.any { it !is String || it.isEmpty() } || ids.toSet().size != ids.size) {
            result.error("invalid_request", "Invalid scan request", null); return
        }
        // Runtime work must not prolong a detached Activity/view's lifetime.
        val observedActivity = activity?.let { WeakReference(it) }
        val observedNativeWindow = activity?.window?.let { WeakReference(it) }
        val observedDecorView = activity?.window?.decorView?.let { WeakReference(it) }
        val observedEpoch = captureEpoch
        val observedWindow = observations[owner]
        val runtimeIds = ids.filterIsInstance<String>().filter { it in RuntimePolicy.ids }
        // A projection can change scope without any Activity focus/lifecycle event.
        // Read its one-shot state at reply time, not before the runtime queue wait.
        val deferRecording = "screenRecording" in ids && runtimeIds.isNotEmpty() &&
            Build.VERSION.SDK_INT >= 35 &&
            context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_RECORDING) == PackageManager.PERMISSION_GRANTED &&
            activity?.let(::foreground) == true
        val signals = EnvironmentSignals(context)
        val findings = ids.filter { it !in RuntimePolicy.ids }.associateWith { raw ->
                val id = raw as String
                val finding = try {
                    when (id) {
                        "screenshot" -> screenshot(owner)
                        "screenRecording" -> if (deferRecording) LocalFinding.error("observationInterrupted") else screenRecording()
                        else -> signals.scan(id)
                    }
                } catch (_: SecurityException) { LocalFinding.error("missingPermission")
                } catch (_: Exception) { LocalFinding.error("nativeFailure") }
                finding.wire(id)
            }.toMutableMap()
        fun reply() {
            // A runtime scan may complete after a pause, rebind or stop/start.
            // Never deliver a previously clean capture sample across that gap.
            val previousActivity = observedActivity?.get()
            val contextChanged = previousActivity == null || !foreground(previousActivity) ||
                activity?.window !== observedNativeWindow?.get() || activity?.window?.decorView !== observedDecorView?.get()
            if (contextChanged && observedWindow != null && observations[owner] === observedWindow) {
                interruptWindow(observedWindow) // A gap discovered at reply time is terminal too.
            }
            if (deferRecording && observedEpoch == captureEpoch && !contextChanged) {
                findings["screenRecording"] = (try { screenRecording() }
                    catch (_: SecurityException) { LocalFinding.error("missingPermission") }
                    catch (_: Exception) { LocalFinding.error("nativeFailure") }).wire("screenRecording")
            }
            for (id in ids.filter { it == "screenshot" || it == "screenRecording" }) {
                if (findings[id]?.get("status") in listOf("detected", "notDetected") &&
                    (observedEpoch != captureEpoch || contextChanged ||
                    (id == "screenshot" && (observations[owner] !== observedWindow || observedWindow?.state?.interrupted == true)))) {
                    // History belongs only to the same observation owner/window.
                    // A stopped/replaced observation must not leak into its successor.
                    findings[id] = (if (id == "screenshot" && observedWindow != null &&
                        observations[owner] === observedWindow) {
                            interruptWindow(observedWindow)
                            observedWindow.state.interruptedFinding()
                        }
                        else LocalFinding.error("observationInterrupted")).wire(id as String)
                }
            }
            result.success(mapOf("schemaVersion" to 1, "contextId" to contextId,
                "findings" to ids.map { findings[it] }))
        }
        if (runtimeIds.isEmpty()) { reply(); return }
        val currentGeneration = generation
        val runtime = RuntimeSignals(context)
        try {
            worker?.execute {
                val observed = runtimeIds.associateWith { runtime.scan(it, args["integrityPolicy"]).wire(it) }
                main.post {
                    if (generation == currentGeneration && channel != null) {
                        findings.putAll(observed)
                        reply()
                    }
                }
            } ?: throw RejectedExecutionException()
        } catch (_: RejectedExecutionException) {
            runtimeIds.forEach { findings[it] = LocalFinding.error("scanLimitExceeded").wire(it) }
            reply()
        }
    }

    private fun foreground(current: Activity): Boolean = activity === current && !paused &&
        !decorDetached && current.hasWindowFocus() && !current.isFinishing && !current.isDestroyed &&
        !current.isInPictureInPictureMode

    private fun sameWindow(window: ScreenshotWindow): Boolean {
        val current = activity ?: return false
        return window.activity.get() === current && window.window.get() === current.window &&
            window.decor.get() === current.window.decorView && foreground(current)
    }

    // Optional host permission is checked explicitly; the library manifest does
    // not force capture permissions into consumers. Cleanup errors remain errors.
    @android.annotation.SuppressLint("MissingPermission")
    private fun startScreenshot(owner: String) {
        if (Build.VERSION.SDK_INT < 34) throw IllegalStateException()
        val previous = observations[owner]
        if (previous != null && !previous.state.interrupted && sameWindow(previous) &&
            context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE) == PackageManager.PERMISSION_GRANTED) return
        release(owner) // Invalidates first; failed cleanup blocks replacement and can be retried.
        val current = activity ?: throw IllegalStateException()
        check(foreground(current))
        if (context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE) != PackageManager.PERMISSION_GRANTED) throw SecurityException()
        check(observations.size < 64)
        val window = ScreenshotWindow(current)
        val weakPlugin = WeakReference(this)
        val weakWindow = WeakReference(window)
        val callback = Activity.ScreenCaptureCallback {
            val plugin = weakPlugin.get()
            val observed = weakWindow.get()
            if (plugin != null && observed != null && plugin.observations[owner] === observed) {
                if (plugin.sameWindow(observed) && !observed.state.interrupted &&
                    plugin.context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE) == PackageManager.PERMISSION_GRANTED) {
                    observed.state.record()
                } else { plugin.interruptWindow(observed) }
            }
        }
        val weakActivity = WeakReference(current)
        window.release = {
            if (Build.VERSION.SDK_INT < 34) throw IllegalStateException()
            // Try removal even if permission was revoked; the OS may still allow
            // cleanup. A failed unregister is retained for explicit stop/retry.
            weakActivity.get()?.unregisterScreenCaptureCallback(callback)
        }
        observations[owner] = window
        try { current.registerScreenCaptureCallback(context.mainExecutor, callback) }
        catch (error: Exception) { interruptWindow(window); throw error }
    }

    private fun screenshot(owner: String): LocalFinding {
        if (Build.VERSION.SDK_INT < 34) return LocalFinding.unsupported("unsupportedOsVersion")
        val window = observations[owner] ?: return LocalFinding.error("observationRequired")
        if (context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE) != PackageManager.PERMISSION_GRANTED) {
            interruptWindow(window)
            return LocalFinding.error("missingPermission")
        }
        if (!sameWindow(window)) interruptWindow(window)
        return window.state.finding(sameWindow(window))
    }

    // A one-shot UID-scoped query, not a persistent recording stream.
    @android.annotation.SuppressLint("MissingPermission")
    private fun screenRecording(): LocalFinding {
        if (Build.VERSION.SDK_INT < 35) return LocalFinding.unsupported("unsupportedOsVersion")
        releaseRecording() // No accumulation after a previous unregister failure.
        if (context.checkSelfPermission(Manifest.permission.DETECT_SCREEN_RECORDING) != PackageManager.PERMISSION_GRANTED) {
            return LocalFinding.error("missingPermission")
        }
        val current = activity ?: return LocalFinding.error("noActivity")
        if (!foreground(current)) {
            interruptWindows()
            return LocalFinding.error("noActivity")
        }
        val callback = Consumer<Int> { } // Holds no plugin, owner, view or captured state.
        val manager = current.windowManager
        recordingCleanup = { manager.removeScreenRecordingCallback(callback) }
        try {
            return when (manager.addScreenRecordingCallback(context.mainExecutor, callback)) {
                WindowManager.SCREEN_RECORDING_STATE_VISIBLE -> LocalFinding.signal(true, "screenCaptured")
                WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE -> LocalFinding.signal(false, "screenCaptured")
                else -> LocalFinding.error("nativeFailure")
            }
        } finally { releaseRecording() }
    }

    private fun releaseRecording() {
        recordingCleanup?.invoke()
        recordingCleanup = null
    }
    private fun releaseWindow(window: ScreenshotWindow) {
        window.state.interrupt()
        window.release?.invoke()
        window.release = null // Only drop the retry handle after successful removal.
    }
    private fun release(owner: String) {
        val window = observations[owner] ?: return
        releaseWindow(window)
        observations.remove(owner)
    }
    private fun interruptWindow(window: ScreenshotWindow) {
        try { releaseWindow(window) } catch (_: Exception) { /* Invalidated; keep cleanup for retry. */ }
    }
    private fun interruptWindows() {
        captureEpoch++
        observations.values.forEach(::interruptWindow)
        try { releaseRecording() } catch (_: Exception) { /* Retain at most one cleanup handle. */ }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        if (activityBinding === binding) return
        if (activity != null) onDetachedFromActivity()
        captureEpoch++
        activityBinding = binding
        activity = binding.activity
        paused = false
        val listener = PluginRegistry.WindowFocusChangedListener { focused ->
            if (activityBinding === binding && !focused) interruptWindows()
        }
        focusListener = listener
        binding.addOnWindowFocusChangedListener(listener)
        // Some Flutter embeddings do not forward Activity focus to binding listeners.
        // Observe the actual decor tree as well; do not replace the host Window callback.
        val decorListener = ViewTreeObserver.OnWindowFocusChangeListener { focused ->
            if (activityBinding === binding && !focused) interruptWindows()
        }
        decorFocusListener = decorListener
        val decor = binding.activity.window.decorView
        observedDecor = decor
        decorDetached = false
        installDecorFocus(decor)
        val attachListener = object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                if (activityBinding !== binding) return
                decorDetached = false
                // A detached decor can acquire a new tree without Activity rebinding.
                installDecorFocus(view)
            }
            override fun onViewDetachedFromWindow(view: View) {
                if (activityBinding !== binding) return
                decorDetached = true
                interruptWindows()
            }
        }
        decorAttachListener = attachListener
        decor.addOnAttachStateChangeListener(attachListener)
        binding.activity.application.registerActivityLifecycleCallbacks(this)
    }
    private fun releaseDecorFocus() {
        decorFocusListener?.let { listener ->
            focusTree?.takeIf { it.isAlive }?.removeOnWindowFocusChangeListener(listener)
            // Pre-attach listeners can be merged into the live observer.
            observedDecor?.viewTreeObserver?.takeIf { it.isAlive && it !== focusTree }
                ?.removeOnWindowFocusChangeListener(listener)
        }
        focusTree = null
    }
    private fun installDecorFocus(view: View) {
        releaseDecorFocus()
        decorFocusListener?.let { listener ->
            focusTree = view.viewTreeObserver.also { it.addOnWindowFocusChangeListener(listener) }
        }
    }
    override fun onDetachedFromActivity() {
        interruptWindows()
        focusListener?.let { activityBinding?.removeOnWindowFocusChangedListener(it) }
        focusListener = null
        decorAttachListener?.let { observedDecor?.removeOnAttachStateChangeListener(it) }
        decorAttachListener = null
        releaseDecorFocus()
        decorFocusListener = null
        observedDecor = null
        decorDetached = true
        activityBinding = null
        activity?.application?.unregisterActivityLifecycleCallbacks(this)
        activity = null
        paused = true
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onActivityStopped(activity: Activity) { if (activity === this.activity) { paused = true; interruptWindows() } }
    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) { if (activity === this.activity) { paused = false; captureEpoch++ } }
    override fun onActivityPaused(activity: Activity) { if (activity === this.activity) { paused = true; interruptWindows() } }
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {
        // Cached/custom hosts can defer ActivityAware detach. Do not retain their
        // destroyed Activity, binding or decor until the engine is finally evicted.
        if (activity === this.activity) onDetachedFromActivity()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = detachEngineResources()

    internal fun detachEngineResources() {
        generation++
        worker?.shutdownNow()
        worker = null
        onDetachedFromActivity()
        observations.clear() // Callback closures hold only weak plugin/session references.
        recordingCleanup = null // Failed OS cleanup remains unconfirmed; callback has no engine references.
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
