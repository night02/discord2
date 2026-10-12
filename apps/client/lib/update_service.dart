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
const officialDownloadsRepository = 'night02/discord2';

/// Only pages owned by the official private repository are valid.
/// No raw EXE/APK URLs, redirects, URL credentials, non-standard ports or query strings.
bool isTrustedVeylorDownload(Uri? uri, {String? releaseVersion}) {
  if (uri == null || uri.scheme != 'https' ||
      uri.host != 'github.com' || uri.userInfo.isNotEmpty ||
      uri.hasPort || uri.hasQuery || uri.hasFragment) {
    return false;
  }
  final path = uri.path;
  if (RegExp(r'^/night02/discord2/actions/runs/[0-9]+$').hasMatch(path)) {
    return true;
  }
  final match=RegExp(
    r'^/night02/discord2/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)-beta(?:\.[1-9][0-9]*)?,
  ).firstMatch(path);
  return match != null && (releaseVersion == null || match.group(1) == releaseVersion);
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
      isTrustedVeylorDownload(uri,releaseVersion:version);
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
,
  ).firstMatch(path);
  return match != null && (releaseVersion == null || match.group(1) == releaseVersion);
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
      isTrustedVeylorDownload(uri,releaseVersion:version);
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
