package dev.securitysdk.security_flutter_example

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/** Explicit Debug-only host: real Activity recreation and real engine.destroy(). */
internal object ReclaimFixture {
    var engine: FlutterEngine? = null
    private var bridge: MethodChannel? = null
    var activity = WeakReference<ReclaimActivity>(null)
    var created = 0
    var destroyed = 0
    var enginesCreated = 0
    var enginesDestroyed = 0
    private const val cacheId = "security-sdk-reclaim-fixture"
    var trimCallbacks = 0
    var ready = false
    fun start(host: Activity, cached: Boolean = false) {
        check(engine == null)
        check(host.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        ready = false
        val next = FlutterEngine(host.applicationContext)
        engine = next; enginesCreated++
        bridge = MethodChannel(next.dartExecutor.binaryMessenger, "security_sdk/reclaim_peer").also {
            it.setMethodCallHandler { call, reply ->
                if (call.method == "ready") { ready = true; reply.success(null) } else reply.notImplemented()
            }
        }
        next.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(), "reclaimMain"))
        if(cached) { restoreCache(); reopen(host) }
        else host.startActivity(Intent(host, ReclaimActivity::class.java))
    }
    fun hasCachedEngine(): Boolean = engine != null && FlutterEngineCache.getInstance().get(cacheId) === engine
    fun reopen(host: Activity) {
        check(engine != null && FlutterEngineCache.getInstance().get(cacheId) === engine && activity.get() == null)
        host.startActivity(FlutterActivity.CachedEngineIntentBuilder(CachedReclaimActivity::class.java,cacheId)
            .destroyEngineWithActivity(false).build(host))
    }
    fun dropCache() { FlutterEngineCache.getInstance().remove(cacheId) }
    fun restoreCache() { FlutterEngineCache.getInstance().put(cacheId,checkNotNull(engine)) }
    fun command(method: String, result: MethodChannel.Result) {
        val current = bridge
        if (current == null) result.error("reclaim_missing", "No test engine", null)
        else current.invokeMethod(method, null, result)
    }
    fun destroy() {
        check(activity.get() == null) // The OS must destroy the child Activity first.
        bridge?.setMethodCallHandler(null); bridge = null
        dropCache()
        engine?.destroy(); if(engine != null) enginesDestroyed++
        engine = null; ready = false
    }
    fun state(): Map<String, Any> = mapOf("activityCreated" to created, "activityDestroyed" to destroyed,
        "engineCreated" to enginesCreated, "engineDestroyed" to enginesDestroyed,
        "cachePresent" to (FlutterEngineCache.getInstance().get(cacheId) != null),
        "cacheMatchesEngine" to (engine != null && FlutterEngineCache.getInstance().get(cacheId) === engine),
        "trimCallbacks" to trimCallbacks, "enginePresent" to (engine != null), "activityPresent" to (activity.get() != null), "ready" to ready,
        "focused" to (activity.get()?.hasWindowFocus() == true))
}

open class ReclaimActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? = ReclaimFixture.engine
    override fun shouldDestroyEngineWithHost() = false
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        ReclaimFixture.created++
        ReclaimFixture.activity = WeakReference(this)
    }
    override fun onTrimMemory(level: Int) {
        ReclaimFixture.trimCallbacks++
        super.onTrimMemory(level)
    }
    override fun onDestroy() {
        super.onDestroy()
        ReclaimFixture.destroyed++
        if(ReclaimFixture.activity.get() === this) ReclaimFixture.activity.clear()
    }
}

/** Uses Flutter's cache resolution, not provideFlutterEngine's custom shortcut. */
class CachedReclaimActivity : ReclaimActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? = null
}
