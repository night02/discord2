import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/update_health.dart';
import 'package:veylor/windows_update_download.dart';

void main() {
  final token = 'abcdef0123456789abcdef0123456789';

  test('start receipt is accepted only with exact token', () async {
    final dir = await Directory.systemTemp.createTemp('veylor-health-test-');
    try {
      final receipt = File('${dir.path}/start.ready');
      await receipt.writeAsString('ready:$token');
      expect(await StartupHandshake.waitForReceipt(
        receipt, token, timeout: const Duration(milliseconds: 200)), isTrue);
      expect(await StartupHandshake.waitForReceipt(
        receipt, '00000000000000000000000000000000',
        timeout: const Duration(milliseconds: 100),
        interval: const Duration(milliseconds: 20)), isFalse);
      expect(await StartupHandshake.waitForReceipt(
        receipt, 'invalid', timeout: const Duration(milliseconds: 50)), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('process exit before health receipt triggers failure', () async {
    final dir = await Directory.systemTemp.createTemp('veylor-health-test-');
    try {
      final receipt = File('${dir.path}/missing.ready');
      expect(await StartupHandshake.waitForReceipt(receipt, token,
        exited: () => true,
        timeout: const Duration(milliseconds: 200)), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('startup timeout does not silently accept absent receipt', () async {
    final dir = await Directory.systemTemp.createTemp('veylor-health-test-');
    try {
      final receipt = File('${dir.path}/missing.ready');
      expect(await StartupHandshake.waitForReceipt(receipt, token,
        timeout: const Duration(milliseconds: 50),
        interval: const Duration(milliseconds: 10)), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('retry only transient HTTP and network interruptions', () {
    for (final e in <Object>[
      const SocketException('offline'),
      TimeoutException('stalled'),
      const IncompleteDownload(),
      const HttpException('GitHub HTTP 503'),
      const HttpException('GitHub HTTP 429'),
    ]) {
      expect(retryableDownloadError(e), isTrue, reason: '$e');
    }
    for (final e in <Object>[
      const HttpException('GitHub HTTP 404'),
      const HttpException('GitHub HTTP 401'),
      const FormatException('Invalid SHA-256'),
      StateError('bad release'),
    ]) {
      expect(retryableDownloadError(e), isFalse, reason: '$e');
    }
  });

  test('foreign and malformed startup flags cannot spoof readiness', () {
    expect(StartupHandshake.validate(const []), isNull);
    expect(StartupHandshake.validate(
      ['--veylor-startup-check', 'unsafe.ready', token]), isNull);
  });
}
