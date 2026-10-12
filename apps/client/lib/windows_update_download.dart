import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'update_service.dart';

/// Only PUBLIC prereleases of this exact project are eligible for in-app download.
/// SHA-256 detects corruption; GitHub repository access controls still determine who
/// is allowed to publish a trusted package. Unsigned EXEs are never called signed.
const _repo = 'night02/discord2';
const maxInstallerBytes = 450 * 1024 * 1024;

class WindowsUpdatePackage {
  WindowsUpdatePackage(this.directory, this.installer, this.sha256, this.version);
  final Directory directory;
  final File installer;
  final String sha256;
  final String version;

  Future<void> discard() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final Uri url;
  final int size;
}

class ReleaseFiles {
  const ReleaseFiles(this.installer, this.checksums);
  final ReleaseAsset installer;
  final ReleaseAsset checksums;
}

/// Release tag must match the version from the trusted update endpoint.
ReleaseFiles parseVeylorWindowsRelease(
    Map<String, dynamic> response, WindowsUpdate update) {
  final tag = update.downloadUrl.pathSegments.last;
  if (!RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+-beta(?:\.[1-9][0-9]*)?$')
          .hasMatch(tag) ||
      response['tag_name'] != tag ||
      response['draft'] != false ||
      response['prerelease'] != true ||
      !isTrustedVeylorDownload(update.downloadUrl, releaseVersion: update.version)) {
    throw const FormatException('Release oficial ou versão inválida.');
  }
  final files = response['assets'];
  if (files is! List) throw const FormatException('Release sem arquivos.');
  final installerName = 'Veylor-v${update.version}-Setup-Windows-x64.exe';
  ReleaseAsset asset(String expected) {
    final matches = files.where((dynamic a) =>
        a is Map && a['name'] == expected && a['state'] == 'uploaded').toList();
    if (matches.length != 1) throw FormatException('Arquivo ausente ou duplicado: $expected');
    final data = matches.single as Map;
    final uri = Uri.tryParse(data['browser_download_url']?.toString() ?? '');
    final size = data['size'];
    final expectedUri = Uri.https('github.com', '/$_repo/releases/download/$tag/$expected');
    if (uri != expectedUri || size is! int || size < 1 ||
        size > (expected == installerName ? maxInstallerBytes : 65536)) {
      throw const FormatException('Arquivo de release com origem ou tamanho inválido.');
    }
    return ReleaseAsset(expected, uri!, size);
  }
  final installer = asset(installerName);
  if (installer.size < 1024 * 1024) throw const FormatException('Instalador muito pequeno.');
  return ReleaseFiles(installer, asset('SHA256SUMS.txt'));
}

String sha256ForInstaller(String manifest, String filename) {
  if (manifest.length > 65536) throw const FormatException('Manifesto grande demais.');
  final found = <String>[];
  for (final line in const LineSplitter().convert(manifest)) {
    final match = RegExp(r'^([a-fA-F0-9]{64})  ([A-Za-z0-9._-]+)$').firstMatch(line.trimRight());
    if (match != null && match.group(2) == filename) found.add(match.group(1)!.toLowerCase());
  }
  if (found.length != 1) throw const FormatException('SHA-256 único não encontrado.');
  return found.single;
}

Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> verifyInstallerDigest(File file, String expected) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected) ||
      !await file.exists() || await sha256OfFile(file) != expected) {
    throw const FormatException('Integridade SHA-256 do instalador não confere.');
  }
}

/// Initial asset download is restricted to the exact GitHub release; only GitHub's
/// asset CDN is accepted after an HTTPS redirect. No general-purpose URL fetch.
bool allowedVeylorAssetRedirect(Uri origin, Uri next) {
  if (origin.scheme != 'https' || next.scheme != 'https' ||
      next.userInfo.isNotEmpty || next.hasFragment || next.hasPort) return false;
  if (origin.host == 'github.com' && next.host == 'github.com') {
    return next == origin;
  }
  return next.host == 'release-assets.githubusercontent.com' ||
      next.host == 'objects.githubusercontent.com';
}

class VeylorWindowsDownloader {
  VeylorWindowsDownloader({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.userAgent = 'Veylor-Windows-Update/0.3.6';
  }
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<HttpClientResponse> _open(Uri uri, {bool asset = false}) async {
    var current = uri;
    for (var redirect = 0; redirect <= 4; redirect++) {
      final request = await _client.getUrl(current);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader,
          asset ? 'application/octet-stream' : 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (!asset || location == null || redirect == 4) {
          throw const FormatException('Redirecionamento inesperado.');
        }
        final next = current.resolve(location);
        if (!allowedVeylorAssetRedirect(current, next)) {
          throw const FormatException('Redirecionamento para origem não confiável.');
        }
        current = next;
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('GitHub HTTP ${response.statusCode}');
      }
      return response;
    }
    throw const FormatException('Redirecionamentos excedidos.');
  }

  Future<List<int>> _smallDownload(Uri uri, int maxBytes, {bool asset = false}) async {
    final response = await _open(uri, asset: asset);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException('Resposta excede o limite.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<WindowsUpdatePackage> prepare(WindowsUpdate update,
      {void Function(int received, int total)? onProgress,
       bool Function()? cancelled}) async {
    if (!isTrustedVeylorDownload(update.downloadUrl, releaseVersion: update.version) ||
        !update.downloadUrl.path.contains('/releases/tag/')) {
      throw const FormatException('Download interno disponível apenas para Releases oficiais.');
    }
    final tag = update.downloadUrl.pathSegments.last;
    final infoUrl = Uri.https('api.github.com', '/repos/$_repo/releases/tags/$tag');
    final metadata = jsonDecode(utf8.decode(await _smallDownload(infoUrl, 256 * 1024)));
    if (metadata is! Map<String, dynamic>) throw const FormatException('Dados inválidos do GitHub.');
    final release = parseVeylorWindowsRelease(metadata, update);
    final checksums = await _smallDownload(release.checksums.url, 65536, asset: true);
    if (checksums.length != release.checksums.size) {
      throw const FormatException('Tamanho do manifesto não confere.');
    }
    final expected = sha256ForInstaller(utf8.decode(checksums), release.installer.name);
    final stage = await Directory.systemTemp.createTemp('veylor-update-');
    final pending = File('${stage.path}/${release.installer.name}.partial');
    try {
      final response = await _open(release.installer.url, asset: true);
      final sink = pending.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (cancelled?.call() == true) throw const FormatException('Download cancelado.');
          received += chunk.length;
          if (received > release.installer.size) {
            throw const FormatException('Arquivo maior que o esperado.');
          }
          sink.add(chunk);
          onProgress?.call(received, release.installer.size);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != release.installer.size) {
        throw const FormatException('Download incompleto.');
      }
      await verifyInstallerDigest(pending, expected);
      final result = File('${stage.path}/${release.installer.name}');
      await pending.rename(result.path);
      return WindowsUpdatePackage(stage, result, expected, update.version);
    } catch (_) {
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }
}
