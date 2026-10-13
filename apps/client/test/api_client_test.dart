import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/api_client.dart';

void main() {
  test('plain-text hosting 404 becomes a readable error with its HTTP status',
      () {
    expect(
        () => decodeApiResponse(404, 'Not Found\n'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.message, 'message',
                contains('Servidor não encontrado'))));
  });

  test(
      'proxy pages and malformed successful responses never expose raw content',
      () {
    const raw = '<html>private proxy diagnostic 123456</html>';
    for (final status in [200, 502, 503]) {
      expect(
          () => decodeApiResponse(status, raw),
          throwsA(isA<ApiException>()
              .having(
                  (e) => e.message, 'private data', isNot(contains('123456')))
              .having((e) => e.message, 'parser internals',
                  isNot(contains('FormatException')))));
    }
    for (final body in ['null', '[]', 'true']) {
      expect(() => decodeApiResponse(200, body), throwsA(isA<ApiException>()));
    }
  });

  test('normal API validation and authentication errors retain their meaning',
      () {
    expect(
        () => decodeApiResponse(
            400, '{"error":"Senha precisa de 10 caracteres"}'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message',
                'Senha precisa de 10 caracteres')));
    expect(
        () => decodeApiResponse(401, '{}'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(decodeApiResponse(200, '{"ok":true,"user":{"username":"tester"}}'), {
      'ok': true,
      'user': {'username': 'tester'}
    });
  });

  test('real HTTP plain-text error and successful JSON follow the same path',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? accept;
    server.listen((request) async {
      accept = request.headers.value(HttpHeaders.acceptHeader);
      if (request.uri.path == '/missing') {
        request.response.statusCode = 404;
        request.response.write('Not Found');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
      }
      await request.response.close();
    });
    final api = Api('http://127.0.0.1:${server.port}');
    await expectLater(
        api.request('GET', '/missing'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 404)));
    expect(await api.request('GET', '/ok'), {'ok': true});
    expect(accept, 'application/json');
  });

  test('unreachable host preserves the session and gives a connection message',
      () async {
    final reservation =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservation.port;
    await reservation.close();
    final api = Api('http://127.0.0.1:$port')..token = 'session-test-fixture';
    await expectLater(
        api.request('GET', '/api/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 0)
            .having((e) => e.message, 'message',
                contains('conectar ao servidor'))));
    expect(api.token, 'session-test-fixture');
  });
}
