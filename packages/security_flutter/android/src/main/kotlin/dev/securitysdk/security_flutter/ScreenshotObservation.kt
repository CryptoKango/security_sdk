package dev.securitysdk.security_flutter

/** An interrupted interval is never silently resumed, even if an event was seen. */
internal class ScreenshotObservation {
    private var seen = false
    var interrupted = false
        private set
    fun record() { if (!interrupted) seen = true }
    fun interrupt() { interrupted = true }
    fun finding(foreground: Boolean): LocalFinding = when {
        interrupted -> LocalFinding.error("observationInterrupted")
        !foreground -> LocalFinding.error("noActivity")
        else -> LocalFinding.signal(seen, "screenshotObserved")
    }
}
