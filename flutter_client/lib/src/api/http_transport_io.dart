import 'dart:convert';
import 'dart:io';

import 'http_transport.dart';

class _IoTransport implements HttpTransport {
  final HttpClient _client = HttpClient();

  @override
  Future<TransportResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) {
    return _send('GET', url, headers: headers);
  }

  @override
  Future<TransportResponse> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    return _send('POST', url, headers: headers, body: body);
  }

  @override
  Future<TransportResponse> put(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    return _send('PUT', url, headers: headers, body: body);
  }

  @override
  Future<TransportResponse> patch(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    return _send('PATCH', url, headers: headers, body: body);
  }

  @override
  Future<TransportResponse> delete(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    return _send('DELETE', url, headers: headers, body: body);
  }

  Future<TransportResponse> _send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await _client.openUrl(method, Uri.parse(url));
    headers.forEach(request.headers.set);

    if (body != null) {
      request.write(body);
    }

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    return TransportResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }
}

HttpTransport createPlatformTransport() => _IoTransport();
