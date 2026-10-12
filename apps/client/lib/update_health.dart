import 'dart:io';

/// A private, single-use readiness handshake. Only files in Veylor's own
/// immediate system-temp staging directories may be written by the app.
class StartupHandshake {
  static final _token = RegExp(r'^[a-f0-9]{32}$');

  static File? validate(List<String> args) {
    if (!Platform.isWindows || args.length != 3 ||
        args[0] != '--veylor-startup-check' || !_token.hasMatch(args[2])) {
      return null;
    }
    final file = File(args[1]).absolute;
    final stage = file.parent;
    final name = stage.path.split(Platform.pathSeparator).last;
    final leaf = file.path.split(Platform.pathSeparator).last;
    if (stage.parent.absolute.path.toLowerCase() !=
            Directory.systemTemp.absolute.path.toLowerCase() ||
        !name.startsWith('veylor-update-') ||
        leaf != 'startup-${args[2]}.ready') {
      return null;
    }
    return file;
  }

  static Future<void> signal(List<String> args) async {
    final file = validate(args);
    if (file == null) return;
    // Don't let a leftover symlink / preexisting receipt pass as readiness.
    if (await file.exists() || await FileSystemEntity.isLink(file.path)) return;
    await file.writeAsString('ready:${args[2]}', flush: true);
  }

  static Future<bool> waitForReceipt(File receipt, String token,
      {Duration timeout = const Duration(seconds: 50),
       Duration interval = const Duration(milliseconds: 250),
       bool Function()? exited}) async {
    if (!_token.hasMatch(token)) return false;
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      if (exited?.call() == true) return false;
      try {
        if (await receipt.exists() &&
            (await receipt.readAsString()).trim() == 'ready:$token') {
          return true;
        }
      } on FileSystemException {
        return false;
      }
      await Future<void>.delayed(interval);
    }
    return false;
  }
}
