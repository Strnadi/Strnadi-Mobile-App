import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class UserController {
  const UserController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path, {Map<String, dynamic>? queryParameters}) {
    return Uri(
      scheme: 'https',
      host: Config.host,
      path: path,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  Future<Response<dynamic>> getUserById(int userId) {
    return _dio.getUri(
      _uri('/users/$userId'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> updateUserById(
      int userId, Map<String, dynamic> body) {
    return _dio.patchUri(
      _uri('/users/$userId'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> deleteUserById(int userId) {
    return _dio.deleteUri(
      _uri('/users/$userId'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> getUserIdFromToken() {
    return _dio.getUri(
      _uri('/users/get-id'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> getProfilePhoto(int userId) {
    return _dio.getUri(
      _uri('/users/$userId/get-profile-photo'),
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> uploadProfilePhoto({
    required int userId,
    required String photoBase64,
    required String format,
  }) {
    return _dio.postUri(
      _uri('/users/$userId/upload-profile-photo'),
      data: <String, dynamic>{
        'photoBase64': photoBase64,
        'format': format,
      },
      options: Options(
        contentType: Headers.jsonContentType,
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
