import 'dart:io';

/// Small, redacted diagnostic trail shared by the Windows sidecar and UI.
/// Never stores access tokens, download URLs, installer paths or credentials.
class UpdateDiagnostics {
  static const _events = <String>{
    'download_start', 'download_retry', 'download_done', 'download_cancel',
    'download_failed', 'package_verified', 'install_confirmed',
    'app_startup_ready', 'app_startup_failed',
    'helper_started', 'helper_rejected', 'backup_created', 'setup_failed',
    'setup_timeout', 'health_passed', 'health_failed',
    'rollback_completed', 'rollback_failed', 'update_completed',
  };

  static Directory get logDirectory {
    final base = Platform.environment['LOCALAPPDATA'];
    final root = base == null || base.isEmpty ? Directory.systemTemp.path : base;
    return Directory('$root${Platform.pathSeparator}Veylor${Platform.pathSeparator}Logs');
  }

  static File get logFile => File(
      '${logDirectory.path}${Platform.pathSeparator}updates.log');

  static Future<void> add(String event) async {
    if (!_events.contains(event)) return;
    try {
      await logDirectory.create(recursive: true);
      final log = logFile;
      if (await log.exists() && await log.length() > 512 * 1024) {
        final old = File('${log.path}.1');
        if (await old.exists()) await old.delete();
        await log.rename(old.path);
      }
      await log.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} $event\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Broken logging must never block launch, update, or recovery.
    }
  }
}
