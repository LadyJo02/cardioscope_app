import 'package:flutter/foundation.dart';

/// 🔧 Enhanced latency tracker with session isolation, summaries, and timestamps.
class LatencyDebug {
  static final Map<String, Map<String, DateTime>> _sessionStarts = {};

  /// Start timing for a key (with optional session ID)
  static void start(String key, [String? note, String? session]) {
    final sid = session ?? "_default";
    _sessionStarts.putIfAbsent(sid, () => {});
    _sessionStarts[sid]![key] = DateTime.now();
    final ts = DateTime.now().toIso8601String().split('T').last;
    debugPrint("⏱️ [$key] START  ${note ?? ''}  [session=$sid | $ts]");
  }

  /// Mark an intermediate step
  static void mark(String key, String mark, {String? session}) {
    final sid = session ?? "_default";
    final t0 = _sessionStarts[sid]?[key];
    if (t0 == null) return;
    final ms = DateTime.now().difference(t0).inMilliseconds;
    debugPrint("📍 [$key] +${ms}ms  — $mark  [session=$sid]");
  }

  /// End a timing
  static void end(String key, [String? note, String? session]) {
    final sid = session ?? "_default";
    final t0 = _sessionStarts[sid]?.remove(key);
    if (t0 == null) return;
    final ms = DateTime.now().difference(t0).inMilliseconds;
    debugPrint("✅ [$key] END  ${note ?? ''}  (Total: $ms ms) [session=$sid]");
  }

  /// Reset a specific session (to avoid overlap between recordings)
  static void resetSession(String session) {
    _sessionStarts.remove(session);
    debugPrint("🧹 Reset latency session: $session");
  }

  /// Print summary for one session
  static void summary(String session, {bool includeMarks = false}) {
    debugPrint("📊 Latency Summary for session=$session");
    final map = _sessionStarts[session];
    if (map == null || map.isEmpty) {
      debugPrint("⚠️  No active timers in this session.");
      return;
    }
    map.forEach((key, start) {
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint("• $key still running (${ms}ms)");
    });
  }
}
