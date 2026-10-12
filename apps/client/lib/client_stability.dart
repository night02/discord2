import 'dart:math';

/// Reconnect automatically, but respect outages and avoid a tight retry loop.
class RetryBackoff {
  int _failures = 0;
  int get failures => _failures;

  Duration nextDelay() {
    final exponent = min(_failures, 4);
    _failures++;
    return Duration(seconds: min(30, 2 * (1 << exponent)));
  }

  void reset() => _failures = 0;
}

/// Idempotency keys prevent duplicate delivery after ambiguous network timeouts.
/// Only one nonce is reused for the same unsent content in the same conversation.
class PendingMessage {
  const PendingMessage({required this.route, required this.content, required this.nonce});
  final String route;
  final String content;
  final String nonce;

  bool matches(String targetRoute, String targetContent) =>
      route == targetRoute && content == targetContent;
}

String createClientNonce() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// WebSocket signals and 30-second polling can overlap; cursor-based pages
/// must remain sorted and must never show the same message twice.
List<Map<String, dynamic>> mergeMessagePages(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> arriving,
) {
  final byId = <int, Map<String, dynamic>>{};
  for (final m in existing) {
    final id = m['id'];
    if (id is int && id >= 0) byId[id] = m;
  }
  for (final m in arriving) {
    final id = m['id'];
    if (id is int && id >= 0) byId[id] = m;
  }
  final keys = byId.keys.toList()..sort();
  return keys.map((id) => byId[id]!).toList(growable: false);
}
