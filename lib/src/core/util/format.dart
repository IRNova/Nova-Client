/// Small formatting helpers shared across screens.
class Fmt {
  const Fmt._();

  /// Human-readable byte count (e.g. `1.4 MB`).
  static String bytes(num value) {
    if (value <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double v = value.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final String n = v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$n ${units[i]}';
  }

  /// Human-readable throughput (e.g. `1.4 MB/s`).
  static String bps(num bytesPerSec) => '${bytes(bytesPerSec)}/s';

  /// `m:ss` clock for elapsed/remaining seconds.
  static String clock(int seconds) {
    if (seconds < 0) seconds = 0;
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// `h:mm:ss` (or `m:ss` under an hour) uptime since [since].
  static String uptime(DateTime? since, {DateTime? now}) {
    if (since == null) return '0:00';
    final int seconds =
        (now ?? DateTime.now()).difference(since).inSeconds.clamp(0, 1 << 31);
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
