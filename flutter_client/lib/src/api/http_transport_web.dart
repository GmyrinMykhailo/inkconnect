import 'dart:html' as html;

import 'http_transport.dart';

class _WebTransport implements HttpTransport {
  @override
  Future<TransportResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return _send(
      url,
      method: 'GET',
      headers: headers,
    );
  }

  @override
  Future<TransportResponse> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    return _send(
      url,
      method: 'POST',
      headers: headers,
      body: body,
    );
  }

  @override
  Future<TransportResponse> put(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    return _send(
      url,
      method: 'PUT',
      headers: headers,
      body: body,
    );
  }

  @override
  Future<TransportResponse> patch(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    return _send(
      url,
      method: 'PATCH',
      headers: headers,
      body: body,
    );
  }

  @override
  Future<TransportResponse> delete(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    return _send(
      url,
      method: 'DELETE',
      headers: headers,
      body: body,
    );
  }

  Future<TransportResponse> _send(
    String url, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    try {
      final response = await html.HttpRequest.request(
        url,
        method: method,
        requestHeaders: headers,
        sendData: body,
      );
      return TransportResponse(
        statusCode: response.status ?? 200,
        body: response.responseText ?? '',
      );
    } on html.ProgressEvent catch (event) {
      final target = event.target;
      if (target is html.HttpRequest) {
        return TransportResponse(
          statusCode: target.status ?? 0,
          body: target.responseText ?? '',
        );
      }
      rethrow;
    }
  }
}

HttpTransport createPlatformTransport() => _WebTransport();
