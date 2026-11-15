/// Cooperative cancellation; it does not promise to abort native work.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  /// Registers a callback and returns an idempotent unsubscribe function.
  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Completes all registered notifications, even if a listener throws.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final listener in listeners) {
      try {
        listener();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
