package dev.securitysdk.security_flutter

/** A gap stays unknown. A callback confirmed before that gap remains a historical fact. */
internal class ScreenshotObservation {
    private var seen = false
    var interrupted = false
        private set
    fun record() { if (!interrupted) seen = true }
    fun interrupt() { interrupted = true }
    fun interruptedFinding(): LocalFinding = LocalFinding.error("observationInterrupted")
        .withValues(mapOf("screenshotObserved" to seen, "observationActive" to false))
    fun finding(foreground: Boolean): LocalFinding = when {
        interrupted -> interruptedFinding()
        !foreground -> LocalFinding.error("noActivity")
        else -> LocalFinding.signal(seen, "screenshotObserved")
            .withValues(mapOf("screenshotObserved" to seen, "observationActive" to true))
    }
}
