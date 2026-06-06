import 'http_transport.dart';

class _UnsupportedTransport implements HttpTransport {
  @override
  Future<TransportResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnsupportedError('HTTP transport is not supported on this platform.');
  }

  @override
  Future<TransportResponse> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is not supported on this platform.');
  }

  @override
  Future<TransportResponse> put(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is not supported on this platform.');
  }

  @override
  Future<TransportResponse> patch(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is not supported on this platform.');
  }

  @override
  Future<TransportResponse> delete(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is not supported on this platform.');
  }
}

HttpTransport createPlatformTransport() => _UnsupportedTransport();
