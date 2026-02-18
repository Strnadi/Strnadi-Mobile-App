import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class AuthController {
  const AuthController();

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

  Future<Response<dynamic>> login({
    required String email,
    required String password,
  }) {
    return _dio.postUri(
      _uri('/auth/login'),
      data: <String, String>{
        'email': email,
        'password': password,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> verifyJwt(String token) {
    return _dio.getUri(
      _uri('/auth/verify-jwt'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> renewJwt(String token) {
    return _dio.getUri(
      _uri('/auth/renew-jwt'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> hasGoogleId(int userId) {
    return _dio.getUri(
      _uri('/auth/has-google-id', queryParameters: <String, int>{
        'userId': userId,
      }),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> hasAppleId(int userId) {
    return _dio.getUri(
      _uri('/auth/has-apple-id', queryParameters: <String, int>{
        'userId': userId,
      }),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> resendVerificationEmail({
    required int userId,
    required String token,
  }) {
    return _dio.getUri(
      _uri('/auth/$userId/resend-verify-email'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> requestPasswordReset(String email) {
    return _dio.getUri(
      _uri('/auth/$email/reset-password'),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }
}
