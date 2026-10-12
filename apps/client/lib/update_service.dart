/// Beta update information. Never downloads or executes binaries automatically.
abstract class AppUpdateInfo {
  const AppUpdateInfo();

  String get version;
  int get build;
  String get notes;
  Uri get downloadUrl;

  bool isNewerThan(int installedBuild) => build > installedBuild;
}

/// Only opens authenticated pages in the project's official private GitHub repo.
bool isTrustedVeylorDownload(Uri? uri) {
  if (uri == null || uri.scheme != 'https' ||
      uri.host != 'github.com' || uri.userInfo.isNotEmpty ||
      uri.hasPort || uri.hasQuery || uri.hasFragment) {
    return false;
  }
  return RegExp(
    r'^/Night0231-creator/discord2/(?:actions/runs/[0-9]+|releases/tag/v[0-9]+\.[0-9]+\.[0-9]+-beta)$',
  ).hasMatch(uri.path);
}

bool _validUpdatePayload(Map<String,dynamic> json, String platform, Uri? uri) {
  final version = json['version'];
  final build = json['build'];
  final notes = json['notes'];
  return json['schema'] == 1 &&
      json['platform'] == platform &&
      json['channel'] == 'beta' &&
      json['installation'] == 'manual' &&
      version is String &&
      RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) &&
      build is int && build > 0 &&
      notes is String && notes.length <= 1500 &&
      isTrustedVeylorDownload(uri);
}

class AndroidUpdate extends AppUpdateInfo {
  const AndroidUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.downloadUrl,
  });

  @override
  final String version;
  @override
  final int build;
  @override
  final String notes;
  @override
  final Uri downloadUrl;

  factory AndroidUpdate.fromJson(Map<String,dynamic> json) {
    final value = json['download_url'];
    final url = value is String ? Uri.tryParse(value) : null;
    if (!_validUpdatePayload(json, 'android', url)) {
      throw const FormatException('Metadados de atualização Android inválidos');
    }
    return AndroidUpdate(
      version: json['version'] as String,
      build: json['build'] as int,
      notes: json['notes'] as String,
      downloadUrl: url!,
    );
  }
}

class WindowsUpdate extends AppUpdateInfo {
  const WindowsUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.downloadUrl,
  });

  @override
  final String version;
  @override
  final int build;
  @override
  final String notes;
  @override
  final Uri downloadUrl;

  factory WindowsUpdate.fromJson(Map<String,dynamic> json) {
    final value = json['download_url'];
    final url = value is String ? Uri.tryParse(value) : null;
    if (!_validUpdatePayload(json, 'windows', url)) {
      throw const FormatException('Metadados de atualização Windows inválidos');
    }
    return WindowsUpdate(
      version: json['version'] as String,
      build: json['build'] as int,
      notes: json['notes'] as String,
      downloadUrl: url!,
    );
  }
}
