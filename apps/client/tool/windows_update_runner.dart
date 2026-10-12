import 'dart:async';
import 'dart:io';
import '../lib/windows_update_download.dart';

/// Runs as a separate, locally compiled Windows EXE after Veylor exits.
/// Never reads network URLs and never executes a package with a mismatched hash.
/// Installer failures restore the previous application DIRECTORY, including
/// its uninstaller. Backup is preserved after success for manual recovery.
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
  final installer = File(options['--installer']!).absolute;
  final installDir = Directory(options['--install-dir']!).absolute;
  final sha = options['--sha256']!;
  final parentPid = int.tryParse(options['--parent-pid']!) ?? 0;
  final version = options['--target-version']!;
  if (parentPid <= 0 || !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
      !installer.path.toLowerCase().endsWith('-setup-windows-x64.exe') ||
      installDir.path == installDir.parent.path ||
      !File('${installDir.path}${Platform.pathSeparator}veylor.exe').existsSync()) {
    return 92;
  }
  final state = File('${installer.parent.path}${Platform.pathSeparator}update-result.txt');
  Future<void> record(String message) async {
    await state.writeAsString('${DateTime.now().toUtc().toIso8601String()} $message\n',
        mode: FileMode.append, flush: true);
  }
  try {
    await verifyInstallerDigest(installer, sha);
    var exited = false;
    for (var i = 0; i < 120; i++) {
      final query = await Process.run('tasklist.exe',
          ['/FI', 'PID eq $parentPid', '/FO', 'CSV', '/NH']);
      if (query.exitCode != 0) throw StateError('Cannot query existing app process.');
      if (!query.stdout.toString().contains(',"$parentPid",')) {
        exited = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!exited) throw StateError('Veylor is still running; installer NOT started.');
    // Recheck just before touching installed files.
    await verifyInstallerDigest(installer, sha);
    final backup = Directory('${installDir.path}.rollback-${DateTime.now().toUtc().millisecondsSinceEpoch}');
    await installDir.rename(backup.path);
    await record('backup-created ${backup.path}');
    try {
      final process = await Process.start(installer.path, [
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/DIR=${installDir.path}'
      ]);
      // A hung installer is NOT considered failed: don't delete its files
      // while it may still be working; preserve the backup for manual recovery.
      final code = await process.exitCode.timeout(const Duration(minutes: 7));
      final exe = File('${installDir.path}${Platform.pathSeparator}veylor.exe');
      final marker = File('${installDir.path}${Platform.pathSeparator}veylor-version.txt');
      if (code != 0 || !await exe.exists() || !await marker.exists() ||
          (await marker.readAsString()).trim() != version) {
        throw StateError('Installer exit=$code, new version not verified.');
      }
      await record('success version=$version backup=${backup.path}');
      await Process.start(exe.path, [], mode: ProcessStartMode.detached);
      return 0;
    } on TimeoutException {
      await record('installer-timeout; backup retained at ${backup.path}; automatic restore skipped');
      return 94;
    } catch (error) {
      await record('installation-failed: $error; trying rollback');
      try {
        if (await installDir.exists()) await installDir.delete(recursive: true);
        await backup.rename(installDir.path);
        await record('rollback-completed');
        final old = File('${installDir.path}${Platform.pathSeparator}veylor.exe');
        if (await old.exists()) {
          await Process.start(old.path, [], mode: ProcessStartMode.detached);
        }
        return 95;
      } catch (restoreError) {
        await record('CRITICAL rollback-failed: $restoreError; backup=${backup.path}');
        return 96;
      }
    }
  } catch (error) {
    await record('update-rejected: $error');
    return 93;
  }
}

Future<void> main(List<String> args) async {
  final code = await runUpdater(args);
  if (code != 0) stderr.writeln('Veylor updater finished with status $code.');
  exitCode = code;
}
