package dev.securitysdk.security_flutter_example

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var originalOrientation: Int? = null
    private var splitReport: Bundle? = null
    private var splitReceiver: android.os.ResultReceiver? = null
    private var splitStarts = 0
    private var splitGeneration = 0
    private var peer: FlutterEngine? = null
    private var pending: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    private val deadline = Runnable {
        pending?.error("peer_timeout", "Peer did not start", null)
        pending = null
        releasePeer()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Example integration fixture only; no channel in distribution builds.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "security_sdk/lifecycle_test")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startSplit" -> {
                        if (android.os.Build.VERSION.SDK_INT < 32) {
                            result.success(mapOf("supported" to false, "reason" to "launchAdjacentRequires32"))
                        } else {
                            splitReport = null
                            splitStarts++
                            val generation = ++splitGeneration
                            val receiver = object : android.os.ResultReceiver(main) {
                                override fun onReceiveResult(code: Int, state: Bundle?) {
                                    if (generation == splitGeneration) splitReport = state
                                }
                            }
                            splitReceiver = receiver
                            try {
                                startActivity(android.content.Intent().setClassName("dev.securitysdk.window_companion",
                                    "dev.securitysdk.window_companion.CompanionActivity")
                                    .putExtra("report", remoteReceiver(receiver))
                                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT or android.content.Intent.FLAG_ACTIVITY_MULTIPLE_TASK))
                                result.success(mapOf("supported" to true))
                            } catch (_: android.content.ActivityNotFoundException) {
                                result.success(mapOf("supported" to false, "reason" to "companionNotInstalled"))
                            }
                        }
                    }
                    "splitState" -> result.success(mapOf("mainMultiWindow" to isInMultiWindowMode, "requests" to splitStarts,
                        "mainFocus" to hasWindowFocus(), "mainResumed" to (lifecycle.currentState == androidx.lifecycle.Lifecycle.State.RESUMED),
                        "peerReceived" to (splitReport != null), "peerMultiWindow" to (splitReport?.getBoolean("multiWindow") == true),
                        "peerFocus" to (splitReport?.getBoolean("focus") == true), "peerClosed" to (splitReport?.getBoolean("closed") == true)))
                    "stopSplit" -> {
                        @Suppress("DEPRECATION")
                        val control = splitReport?.getParcelable<android.os.ResultReceiver>("control")
                        control?.send(2, Bundle())
                        startActivity(android.content.Intent(this, MainActivity::class.java)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                        result.success(null)
                    }
                    "startPeer" -> {
                        if (peer != null) {
                            result.error("peer_exists", "Peer already running", null)
                        } else {
                            val engine = FlutterEngine(this)
                            peer = engine
                            pending = result
                            MethodChannel(engine.dartExecutor.binaryMessenger, "security_sdk/lifecycle_peer")
                                .setMethodCallHandler { message, response ->
                                    if (message.method == "ready") {
                                        main.removeCallbacks(deadline)
                                        pending?.success(message.arguments)
                                        pending = null
                                        response.success(null)
                                    } else response.notImplemented()
                                }
                            main.postDelayed(deadline, 20000)
                            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "lifecyclePeerMain"))
                        }
                    }
                    "interruptCapture" -> {
                        // Real OS focus transitions, no direct calls into the plugin.
                        val dialog = android.app.Dialog(this)
                        dialog.show()
                        main.postDelayed({
                            dialog.dismiss()
                            main.postDelayed({ result.success(null) }, 300)
                        }, 500)
                    }
                    "uiState" -> result.success(mapOf("orientation" to resources.configuration.orientation,
                        "focus" to hasWindowFocus(), "pip" to isInPictureInPictureMode,
                        "resumed" to (lifecycle.currentState == androidx.lifecycle.Lifecycle.State.RESUMED)))
                    "rotate" -> {
                        if (originalOrientation == null) originalOrientation = requestedOrientation
                        val portrait = resources.configuration.orientation != android.content.res.Configuration.ORIENTATION_PORTRAIT
                        requestedOrientation = if (portrait) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        result.success(if (portrait) android.content.res.Configuration.ORIENTATION_PORTRAIT
                            else android.content.res.Configuration.ORIENTATION_LANDSCAPE)
                    }
                    "restoreOrientation" -> { originalOrientation?.let { requestedOrientation = it }; result.success(null) }
                    "enterPip" -> {
                        result.success(if (android.os.Build.VERSION.SDK_INT >= 26 &&
                            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE))
                            enterPictureInPictureMode(android.app.PictureInPictureParams.Builder().build()) else false)
                    }
                    "leavePip" -> {
                        if (isInPictureInPictureMode) startActivity(android.content.Intent(this, MainActivity::class.java)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                            .setAction(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_LAUNCHER))
                        result.success(null)
                    }
                    "stopPeer" -> { releasePeer(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    // Marshal to the framework class: the other APK cannot load our anonymous subclass.
    private fun remoteReceiver(receiver: android.os.ResultReceiver): android.os.ResultReceiver {
        val parcel = android.os.Parcel.obtain()
        return try {
            receiver.writeToParcel(parcel, 0)
            parcel.setDataPosition(0)
            android.os.ResultReceiver.CREATOR.createFromParcel(parcel)
        } finally { parcel.recycle() }
    }

    private fun releasePeer() {
        main.removeCallbacks(deadline)
        pending?.error("peer_stopped", "Peer stopped", null)
        pending = null
        peer?.destroy()
        peer = null
    }

    override fun onDestroy() {
        releasePeer()
        super.onDestroy()
    }
}
