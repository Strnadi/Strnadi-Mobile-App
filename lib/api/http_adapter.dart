import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as package_http;
import 'package:strnadi/api/dio_client.dart';

typedef Response = package_http.Response;

typedef ClientException = package_http.ClientException;

Future<Response> get(Uri url, {Map<String, String>? headers}) async {
  return _request('GET', url, headers: headers);
}

Future<Response> head(Uri url, {Map<String, String>? headers}) async {
  return _request('HEAD', url, headers: headers);
}

Future<Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _request('DELETE', url,
      headers: headers, body: body, encoding: encoding);
}

Future<Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _request('POST', url,
      headers: headers, body: body, encoding: encoding);
}

Future<Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _request('PATCH', url,
      headers: headers, body: body, encoding: encoding);
}

Future<Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _request('PUT', url, headers: headers, body: body, encoding: encoding);
}

Future<Response> _request(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  try {
    final dio.Dio client = ApiDioClient.instance;
    final dynamic data = _normalizeBody(body, encoding, headers);

    final dioResponse = await client.requestUri<dynamic>(
      url,
      data: data,
      options: dio.Options(
        method: method,
        headers: headers,
        responseType: dio.ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );

    return _toHttpResponse(
      method: method,
      url: url,
      response: dioResponse,
    );
  } on dio.DioException catch (e) {
    throw package_http.ClientException(
        e.message ?? 'Network request failed', url);
  }
}

Response _toHttpResponse({
  required String method,
  required Uri url,
  required dio.Response<dynamic> response,
}) {
  final Uint8List bodyBytes = _normalizeResponseBody(response.data);
  final Map<String, String> headers = _flattenHeaders(response.headers);

  return package_http.Response.bytes(
    bodyBytes,
    response.statusCode ?? 0,
    headers: headers,
    request: package_http.Request(method, url),
    reasonPhrase: response.statusMessage,
    isRedirect: response.isRedirect,
    persistentConnection: true,
  );
}

Map<String, String> _flattenHeaders(dio.Headers dioHeaders) {
  final Map<String, String> out = <String, String>{};
  dioHeaders.forEach((key, values) {
    if (values.isNotEmpty) {
      out[key] = values.join(',');
    }
  });
  return out;
}

Uint8List _normalizeResponseBody(dynamic data) {
  if (data == null) {
    return Uint8List(0);
  }
  if (data is Uint8List) {
    return data;
  }
  if (data is List<int>) {
    return Uint8List.fromList(data);
  }
  if (data is String) {
    return Uint8List.fromList(utf8.encode(data));
  }
  if (data is Map || data is List) {
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }
  return Uint8List.fromList(utf8.encode(data.toString()));
}

dynamic _normalizeBody(
  Object? body,
  Encoding? encoding,
  Map<String, String>? headers,
) {
  if (body == null) {
    return null;
  }
  if (body is String ||
      body is dio.FormData ||
      body is List<int> ||
      body is Map<String, dynamic> ||
      body is List<dynamic>) {
    return body;
  }

  if (body is Map) {
    return body.map((key, value) => MapEntry('$key', value));
  }

  if (body is Iterable) {
    return body.toList();
  }

  final Encoding resolvedEncoding = encoding ?? utf8;
  final String contentType =
      headers?['Content-Type'] ?? headers?['content-type'] ?? '';
  if (contentType.contains('application/json')) {
    return jsonEncode(body);
  }

  return resolvedEncoding.encode(body.toString());
}
