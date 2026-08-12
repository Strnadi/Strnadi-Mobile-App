import 'package:dio/dio.dart';
import 'package:strnadi/exceptions.dart';

bool _isRedirect(int? statusCode) =>
    statusCode != null && statusCode >= 300 && statusCode < 400;

bool _preservesPostOnRedirect(int? statusCode) =>
    statusCode == 307 || statusCode == 308;

bool _sameOrigin(Uri first, Uri second) {
  return second.scheme == 'https' &&
      second.scheme == first.scheme &&
      second.host == first.host &&
      second.port == first.port;
}

void _requireHttpsOrigin(Uri uri, String operation) {
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    throw UploadException(
      '$operation requires a valid HTTPS backend origin.',
      502,
    );
  }
}

Uri resolveSameOriginHttpsRedirect({
  required Uri initialUri,
  required String? location,
  required String operation,
}) {
  _requireHttpsOrigin(initialUri, operation);
  if (location == null || location.trim().isEmpty) {
    throw UploadException(
      '$operation redirected without a location.',
      502,
    );
  }
  final Uri redirected;
  try {
    redirected = initialUri.resolve(location.trim());
  } on FormatException {
    throw UploadException(
      '$operation redirected to an invalid location.',
      502,
    );
  }
  if (!_sameOrigin(initialUri, redirected)) {
    throw UploadException(
      '$operation redirected outside the configured backend.',
      502,
    );
  }
  return redirected;
}

/// Replays a JSON POST at most once for a same-origin HTTPS redirect.
///
/// Automatic redirect handling can turn a POST into a body-less GET or refuse
/// to replay 307/308. Rebuilding the request here preserves the body, captured
/// authorization, and idempotency key.
Future<Response<dynamic>> postJsonWithSameOriginRedirect({
  required Dio dio,
  required Uri uri,
  required Map<String, Object?> body,
  required Map<String, Object?> headers,
  required Future<void> Function() beforePost,
}) async {
  _requireHttpsOrigin(uri, 'JSON upload');

  Options options() => Options(
        contentType: Headers.jsonContentType,
        headers: Map<String, Object?>.from(headers),
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null,
      );

  Future<Response<dynamic>> post(Uri target) async {
    final Map<String, Object?> requestBody = Map<String, Object?>.from(body);
    final Options requestOptions = options();
    await beforePost();
    return dio.postUri(
      target,
      data: requestBody,
      options: requestOptions,
    );
  }

  Response<dynamic> response = await post(uri);
  if (!_isRedirect(response.statusCode)) {
    return response;
  }
  if (!_preservesPostOnRedirect(response.statusCode)) {
    throw UploadException(
      'JSON upload received unsupported redirect status '
      '${response.statusCode}.',
      502,
    );
  }

  final Uri redirected = resolveSameOriginHttpsRedirect(
    initialUri: response.requestOptions.uri,
    location: response.headers.value('location'),
    operation: 'JSON upload',
  );

  response = await post(redirected);
  if (_isRedirect(response.statusCode)) {
    throw UploadException(
      'JSON upload redirected more than once.',
      502,
    );
  }
  return response;
}

/// Replays one same-origin HTTPS redirect by invoking [post] again.
///
/// Multipart bodies are single-use streams. Callers must construct the body
/// inside [post], so every invocation receives fresh `FormData` and a fresh
/// stream from the same immutable snapshot while retaining the captured
/// authorization and idempotency key.
Future<Response<dynamic>> postRebuiltWithSameOriginRedirect({
  required Future<Response<dynamic>> Function(String? overrideUrl) post,
  required String operation,
}) async {
  Response<dynamic> response = await post(null);
  if (!_isRedirect(response.statusCode)) {
    return response;
  }
  if (!_preservesPostOnRedirect(response.statusCode)) {
    throw UploadException(
      '$operation received unsupported redirect status '
      '${response.statusCode}.',
      502,
    );
  }

  final Uri redirected = resolveSameOriginHttpsRedirect(
    initialUri: response.requestOptions.uri,
    location: response.headers.value('location'),
    operation: operation,
  );
  response = await post(redirected.toString());
  if (_isRedirect(response.statusCode)) {
    throw UploadException(
      '$operation redirected more than once.',
      502,
    );
  }
  return response;
}
