import 'http_transport_stub.dart'
    if (dart.library.io) 'http_transport_io.dart'
    if (dart.library.html) 'http_transport_web.dart';

abstract class HttpTransport {
  Future<TransportResponse> get(
    String url, {
    Map<String, String> headers = const {},
  });

  Future<TransportResponse> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });

  Future<TransportResponse> put(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });

  Future<TransportResponse> patch(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });

  Future<TransportResponse> delete(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });
}

class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

HttpTransport createTransport() => createPlatformTransport();
