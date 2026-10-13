import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

String _statusMessage(int status) => switch (status) {
      401 =>
        'Sua sessão expirou ou as credenciais são inválidas. Entre novamente.',
      403 => 'Você não tem permissão para essa ação.',
      404 =>
        'Servidor não encontrado. Confira o endereço do servidor e tente novamente.',
      429 => 'Muitas tentativas. Aguarde um pouco e tente novamente.',
      >= 500 =>
        'Servidor temporariamente indisponível. Aguarde um pouco e tente novamente.',
      _ => 'Não foi possível concluir a solicitação. Tente novamente.',
    };

/// Hosting proxies can return HTML or plain text instead of the API's JSON.
/// Never put that raw body (possibly containing diagnostics) in the interface.
Map<String, dynamic> decodeApiResponse(int status, String text) {
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    if (status >= 400) throw ApiException(status, _statusMessage(status));
    throw const ApiException(502,
        'Resposta inválida do servidor. Confira o endereço do servidor e tente novamente.');
  }
  if (status >= 400) {
    final detail = value is Map ? value['error'] : null;
    throw ApiException(
        status,
        detail is String && detail.trim().isNotEmpty && detail.length <= 500
            ? detail
            : _statusMessage(status));
  }
  if (value is! Map<String, dynamic>) {
    throw const ApiException(502,
        'Resposta inválida do servidor. Confira o endereço do servidor e tente novamente.');
  }
  return value;
}

class Api {
  Api(this.baseUrl);
  String baseUrl;
  String? token;

  Future<Map<String, dynamic>> request(String method, String route,
      [Map<String, dynamic>? body]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse(baseUrl + route));
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null)
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) req.write(jsonEncode(body));
      final response = await req.close().timeout(const Duration(seconds: 15));
      final payload = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      return decodeApiResponse(response.statusCode, payload);
    } on TimeoutException {
      throw const ApiException(0,
          'O servidor demorou para responder. Ele pode estar iniciando; aguarde e tente novamente.');
    } on SocketException {
      throw const ApiException(0,
          'Não foi possível conectar ao servidor. Verifique sua conexão e tente novamente.');
    } on HandshakeException {
      throw const ApiException(
          0, 'Não foi possível estabelecer uma conexão segura com o servidor.');
    } on HttpException {
      throw const ApiException(
          0, 'A conexão com o servidor foi interrompida. Tente novamente.');
    } finally {
      client.close(force: true);
    }
  }
}
