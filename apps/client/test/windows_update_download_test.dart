import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/update_service.dart';
import 'package:veylor/windows_update_download.dart';

void main() {
  WindowsUpdate update({String version = '0.3.6'}) =>
      WindowsUpdate.fromJson({
        'schema': 1, 'platform': 'windows', 'channel': 'beta',
        'installation': 'manual', 'version': version, 'build': 10,
        'notes': 'Atualização protegida',
        'download_url': 'https://github.com/night02/discord2/releases/tag/v$version-beta.123',
      });

  Map<String, dynamic> release(String version) {
    final tag = 'v$version-beta.123';
    Map<String, dynamic> asset(String name, int size) => {
      'name': name,
      'state': 'uploaded',
      'size': size,
      'browser_download_url':
          'https://github.com/night02/discord2/releases/download/$tag/$name',
    };
    return {
      'tag_name': tag, 'draft': false, 'prerelease': true,
      'assets': [
        asset('Veylor-v$version-Setup-Windows-x64.exe', 2097152),
        asset('SHA256SUMS.txt', 140),
      ],
    };
  }

  test('only version-matching public beta release and its two assets', () {
    final pkg = parseVeylorWindowsRelease(release('0.3.6'), update());
    expect(pkg.installer.name, 'Veylor-v0.3.6-Setup-Windows-x64.exe');
    expect(pkg.checksums.name, 'SHA256SUMS.txt');
    expect(() => parseVeylorWindowsRelease(release('0.3.5'), update()),
        throwsFormatException);
    expect(() => parseVeylorWindowsRelease(
        release('0.3.6')..['draft'] = true, update()), throwsFormatException);
    expect(() => parseVeylorWindowsRelease(
        release('0.3.6')..['prerelease'] = false, update()), throwsFormatException);
  });

  test('missing, duplicated or forged assets are rejected', () {
    final name = 'Veylor-v0.3.6-Setup-Windows-x64.exe';
    final missing = release('0.3.6');
    (missing['assets'] as List).removeAt(0);
    expect(() => parseVeylorWindowsRelease(missing, update()), throwsFormatException);
    final duplicate = release('0.3.6');
    final assets = duplicate['assets'] as List;
    assets.add(Map<String, dynamic>.from(assets.first as Map));
    expect(() => parseVeylorWindowsRelease(duplicate, update()), throwsFormatException);
    final forged = release('0.3.6');
    (forged['assets'] as List).first['browser_download_url'] =
        'https://attack.invalid/$name';
    expect(() => parseVeylorWindowsRelease(forged, update()), throwsFormatException);
    final oversize = release('0.3.6');
    (oversize['assets'] as List).first['size'] = maxInstallerBytes + 1;
    expect(() => parseVeylorWindowsRelease(oversize, update()), throwsFormatException);
  });

  test('manifest exact filename, unique digest, and malformed lines', () {
    const file = 'Veylor-v0.3.6-Setup-Windows-x64.exe';
    const checksum = 'a2c53a86b68a4d596547a5912b74a213a20f9c553b43ff6ae166a06ca2d0f5c9';
    expect(sha256ForInstaller('$checksum  $file\n', file), checksum);
    expect(() => sha256ForInstaller('$checksum  $file\n$checksum  $file\n', file),
        throwsFormatException);
    expect(() => sha256ForInstaller('$checksum  something.exe\n', file),
        throwsFormatException);
    expect(() => sha256ForInstaller('not-a-hash  $file\n', file),
        throwsFormatException);
  });

  test('allow only GitHub asset CDN after HTTPS response', () {
    final origin = Uri.parse('https://github.com/night02/discord2/releases/download/v0.3.6-beta.123/a.exe');
    expect(allowedVeylorAssetRedirect(origin,
        Uri.parse('https://release-assets.githubusercontent.com/a?token=x')), isTrue);
    for (final invalid in [
      'http://release-assets.githubusercontent.com/a',
      'https://release-assets.githubusercontent.com:8443/a',
      'https://username:pw@release-assets.githubusercontent.com/a',
      'https://attacker.test/file',
      'https://github.com.attacker.test/file',
    ]) {
      expect(allowedVeylorAssetRedirect(origin, Uri.parse(invalid)), isFalse,
          reason: invalid);
    }
  });

  test('tampered on-disk executable fails digest validation', () async {
    final dir = await Directory.systemTemp.createTemp('veylor-digest-test-');
    try {
      final exe = File('${dir.path}${Platform.pathSeparator}installer.exe');
      await exe.writeAsBytes([0, 1, 2, 3, 4]);
      final expected = await sha256OfFile(exe);
      await verifyInstallerDigest(exe, expected);
      await exe.writeAsBytes([0, 1, 2, 3, 5]);
      await expectLater(verifyInstallerDigest(exe, expected), throwsFormatException);
      await expectLater(verifyInstallerDigest(exe, 'wrong'), throwsFormatException);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
