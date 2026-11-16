package dev.securitysdk.security_flutter_example

import android.app.Activity
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.ViewTreeObserver
import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import java.lang.ref.WeakReference

/** Explicit Debug fixture only. No SDK focus filtering and no screenshot contents. */
@android.annotation.TargetApi(34)
internal class CaptureCallbackProbe(private val activity: Activity) {
    private val events = mutableListOf<Map<String, Any>>()
    private val initialWindow = WeakReference(activity.window)
    private val initialDecor = WeakReference(activity.window.decorView)
    private val startedAt = SystemClock.elapsedRealtime()
    private var truncated = false
    private var count = 0
    private var registered = false
    private var cleanupPending = false
    private val callback = Activity.ScreenCaptureCallback {
        if (registered) {
            count++
            note("screenshot", activity.hasWindowFocus())
        }
    }
    private val focus = ViewTreeObserver.OnWindowFocusChangeListener { note("focus", it) }
    private var tree: ViewTreeObserver? = null
    fun note(kind: String, value: Boolean) {
        if (!registered) return
        if (events.size < 64) events.add(mapOf("kind" to kind, "value" to value,
            "sequence" to events.size, "elapsedMs" to (SystemClock.elapsedRealtime() - startedAt)))
        else truncated = true
    }
    fun start() {
        cleanupPending = true
        activity.registerScreenCaptureCallback(activity.mainExecutor, callback)
        registered = true
        tree = activity.window.decorView.viewTreeObserver.also { it.addOnWindowFocusChangeListener(focus) }
        note("start", activity.hasWindowFocus())
    }
    fun snapshot(): Map<String, Any> = mapOf("callbacks" to count, "registered" to registered,
        "cleanupPending" to cleanupPending, "focused" to activity.hasWindowFocus(),
        "resumed" to ((activity as? LifecycleOwner)?.lifecycle?.currentState == Lifecycle.State.RESUMED),
        "attached" to activity.window.decorView.isAttachedToWindow,
        "sameWindow" to (initialWindow.get() === activity.window && initialDecor.get() === activity.window.decorView),
        "inPictureInPicture" to activity.isInPictureInPictureMode,
        "secureWindow" to (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0),
        "permissionGranted" to (activity.checkSelfPermission(android.Manifest.permission.DETECT_SCREEN_CAPTURE) == PackageManager.PERMISSION_GRANTED),
        "eventsTruncated" to truncated, "events" to events.toList())
    fun stop() {
        // Ignore a callback already queued when stop is requested, even if cleanup fails.
        registered = false
        tree?.takeIf { it.isAlive }?.removeOnWindowFocusChangeListener(focus)
        tree = null
        if (cleanupPending) activity.unregisterScreenCaptureCallback(callback)
        cleanupPending = false
    }
}
