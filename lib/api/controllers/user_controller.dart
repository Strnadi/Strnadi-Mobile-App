import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class UserController {
  const UserController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? host,
  }) {
    return Uri(
      scheme: 'https',
      host: host ?? Config.host,
      path: path,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  Options _authenticatedOptions({
    String? accessToken,
    ResponseType? responseType,
  }) {
    return Options(
      contentType: Headers.jsonContentType,
      responseType: responseType,
      followRedirects: false,
      maxRedirects: 0,
      validateStatus: (int? status) => status != null && status < 500,
      headers: <String, Object?>{
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      extra: const <String, Object>{'authRequired': true},
    );
  }

  Future<Response<dynamic>> getUserById(
    int userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri('/users/$userId', host: host),
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> updateUserById(
    int userId,
    Map<String, dynamic> body, {
    String? accessToken,
    String? host,
  }) {
    return _dio.patchUri(
      _uri('/users/$userId', host: host),
      data: body,
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> deleteUserById(
    int userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.deleteUri(
      _uri('/users/$userId', host: host),
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> getUserIdFromToken() {
    return _dio.getUri(
      _uri('/users/get-id'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> getProfilePhoto(
    int userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri('/users/$userId/get-profile-photo', host: host),
      options: _authenticatedOptions(
        accessToken: accessToken,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> uploadProfilePhoto({
    required int userId,
    required String photoBase64,
    required String format,
    String? accessToken,
    String? host,
  }) {
    return _dio.postUri(
      _uri('/users/$userId/upload-profile-photo', host: host),
      data: <String, dynamic>{
        'photoBase64': photoBase64,
        'format': format,
      },
      options: _authenticatedOptions(
        accessToken: accessToken,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> getUserByEmail(String email) {
    return _dio.getUri(
      _uri('/users/$email'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> checkEmailExists(String email) {
    return _dio.getUri(
      _uri('/users/exists', queryParameters: <String, String>{
        'email': email,
      }),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }
}
