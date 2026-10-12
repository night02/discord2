import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:veylor/update_diagnostics.dart';
import 'package:veylor/update_health.dart';
import 'package:veylor/windows_update_download.dart';

/// Standalone updater: waits for the old process, makes a backup, installs a
/// verified binary, and probes the new Flutter UI before declaring success.
/// A failed boot rolls back files. Registry changes are outside this scope.
Future<int> runUpdater(List<String> args) async {
  if (!Platform.isWindows) return 90;
  final options = <String, String>{};
  if (args.length.isOdd) return 91;
  for (var i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || options.containsKey(args[i])) return 91;
    options[args[i]] = args[i + 1];
  }
  const required = <String>[
    '--installer', '--sha256', '--install-dir', '--parent-pid', '--target-version'
  ];
  if (required.any((key) => (options[key] ?? '').isEmpty)) return 91;
  // The fixture switch is only allowed for the CI's no-relaunch test mode.
  final noRelaunch = options['--no-relaunch'] == 'true';
  final fakeFailure = options['--test-startup-fail'] == 'true';
  if (fakeFailure && !noRelaunch) return 91;

  final installer = File(options['--installer']!).absolute;
  final installDir = Directory(options['--install-dir']!).absolute;
  final sha = options['--sha256']!;
  final parentPid = int.tryParse(options['--parent-pid']!) ?? 0;
  final version = options['--target-version']!;
  if (parentPid <= 0 ||
      !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
      !installer.path.toLowerCase().endsWith('-setup-windows-x64.exe') ||
      installDir.path == installDir.parent.path ||
      !File('${installDir.path}${Platform.pathSeparator}veylor.exe').existsSync() ||
      !File('${installDir.path}${Platform.pathSeparator}unins000.exe').existsSync()) {
    return 92;
  }

  final state = File('${installer.parent.path}${Platform.pathSeparator}update-result.txt');
  Future<void> record(String message) async {
    try {
      await state.writeAsString(
          '${DateTime.now().toUtc().toIso8601String()} $message\n',
          mode: FileMode.append, flush: true);
    } on FileSystemException {
      // The durable app log is best effort as well.
    }
  }

  await UpdateDiagnostics.add('helper_started');
  try {
    await verifyInstallerDigest(installer, sha);
    var parentExited = false;
    for (var i = 0; i < 120; i++) {
      final query = await Process.run('tasklist.exe',
          ['/FI', 'PID eq $parentPid', '/FO', 'CSV', '/NH']);
      if (query.exitCode != 0) throw StateError('Cannot inspect old Veylor PID.');
      if (!query.stdout.toString().contains(',"$parentPid",')) {
        parentExited = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!parentExited) throw StateError('Old Veylor process still running.');
    await verifyInstallerDigest(installer, sha);

    final backup = Directory(
        '${installDir.path}.rollback-${DateTime.now().toUtc().millisecondsSinceEpoch}');
    await installDir.rename(backup.path);
    await UpdateDiagnostics.add('backup_created');
    await record('backup-created ${backup.path}');

    Process? launched;
    bool launchedExited = false;
    try {
      final setup = await Process.start(installer.path, [
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
        '/DIR=${installDir.path}'
      ]);
      // A timed-out installer might still be writing. Do not touch its files.
      final code = await setup.exitCode.timeout(const Duration(minutes: 7));
      final exe = File('${installDir.path}${Platform.pathSeparator}veylor.exe');
      final marker = File('${installDir.path}${Platform.pathSeparator}veylor-version.txt');
      if (code != 0 || !await exe.exists() || !await marker.exists() ||
          (await marker.readAsString()).trim() != version) {
        throw StateError('Installer or version check failed.');
      }

      if (fakeFailure) {
        throw StateError('Simulated startup failure in CI.');
      }
      if (!noRelaunch) {
        final rand = Random.secure();
        final token = List<int>.generate(16, (_) => rand.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final receipt = File(
            '${installer.parent.path}${Platform.pathSeparator}startup-$token.ready');
        if (await receipt.exists()) await receipt.delete();
        launched = await Process.start(exe.path,
          ['--veylor-startup-check', receipt.path, token],
          workingDirectory: installDir.path);
        unawaited(launched.exitCode.then((_) {
          launchedExited = true;
        }));
        final ready = await StartupHandshake.waitForReceipt(
          receipt, token, exited: () => launchedExited,
          timeout: const Duration(seconds: 60));
        // Short grace period detects an immediate post-frame crash.
        if (ready) await Future<void>.delayed(const Duration(seconds: 3));
        if (!ready || launchedExited) {
          await UpdateDiagnostics.add('health_failed');
          throw StateError('New Veylor did not stay ready after startup.');
        }
        await UpdateDiagnostics.add('health_passed');
      }

      await UpdateDiagnostics.add('update_completed');
      await record('success version=$version backup=${backup.path}');
      return 0;
    } on TimeoutException {
      await UpdateDiagnostics.add('setup_timeout');
      await record('setup-timeout; backup preserved for manual recovery');
      return 94;
    } catch (_) {
      await UpdateDiagnostics.add('setup_failed');
      await record('setup-or-startup-failed; attempting rollback');
      if (launched != null && !launchedExited) {
        launched.kill();
        try {
          await launched.exitCode.timeout(const Duration(seconds: 8));
        } on TimeoutException {
          await UpdateDiagnostics.add('rollback_failed');
          await record('rollback-refused: updated process is still running; backup retained');
          return 97;
        }
      }
      try {
        if (await installDir.exists()) await installDir.delete(recursive: true);
        await backup.rename(installDir.path);
        await UpdateDiagnostics.add('rollback_completed');
        await record('rollback-completed');
        final old = File('${installDir.path}${Platform.pathSeparator}veylor.exe');
        if (await old.exists() && !noRelaunch) {
          await Process.start(old.path, [], mode: ProcessStartMode.detached);
        }
        return 95;
      } catch (_) {
        await UpdateDiagnostics.add('rollback_failed');
        await record('CRITICAL rollback-failed; backup retained');
        return 96;
      }
    }
  } catch (_) {
    await UpdateDiagnostics.add('helper_rejected');
    await record('update-rejected; original installation not intentionally altered');
    return 93;
  }
}

Future<void> main(List<String> args) async {
  exitCode = await runUpdater(args);
  if (exitCode != 0) stderr.writeln('Veylor updater status $exitCode');
}
