import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/user_identity.dart';
import 'package:strnadi/api/models/administration_profile.dart';
import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class UserController {
  const UserController();

  Dio get _dio => ApiDioClient.instance;

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

  Future<Response<dynamic>> _ownAdministrationProfile(
    Object userId, {
    String? accessToken,
    String? host,
    Map<String, dynamic>? body,
  }) async {
    final snapshot = await activatedAuthSessions.capture();
    if (snapshot == null ||
        parseUserId(userId) != parseUserId(snapshot.userId) ||
        (accessToken != null && accessToken != snapshot.accessToken) ||
        (host != null && host != Config.host)) {
      throw StateError('Only the active account profile is available.');
    }
    final environment = Config.dataEnvironment;
    final response = await _dio.requestUri<dynamic>(
      ApiDioClient.uri(
        '/account/profile',
        host: Config.administrationHost,
      ).replace(
        queryParameters: {'projectId': Config.administration!.projectId},
      ),
      data: body == null ? null : administrationProfilePatch(body),
      options: _authenticatedOptions(accessToken: snapshot.accessToken)
        ..method = body == null ? 'GET' : 'PATCH',
    );
    if (Config.dataEnvironment != environment ||
        !await activatedAuthSessions.isCurrent(snapshot)) {
      throw StateError('Account changed while loading the profile.');
    }
    if (response.statusCode == 200) {
      response.data = normalizeAdministrationProfile(
        response.data,
        expectedUserId: snapshot.userId,
      );
    }
    return response;
  }

  Future<Response<dynamic>> getUserById(
    Object userId, {
    String? accessToken,
    String? host,
  }) {
    if (Config.usesAdministration) {
      return _ownAdministrationProfile(
        userId,
        accessToken: accessToken,
        host: host,
      );
    }
    return _dio.getUri(
      ApiDioClient.uri('/users/$userId', host: host),
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> updateUserById(
    Object userId,
    Map<String, dynamic> body, {
    String? accessToken,
    String? host,
  }) {
    if (Config.usesAdministration) {
      return _ownAdministrationProfile(
        userId,
        accessToken: accessToken,
        host: host,
        body: body,
      );
    }
    return _dio.patchUri(
      ApiDioClient.uri('/users/$userId', host: host),
      data: body,
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> deleteUserById(
    Object userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.deleteUri(
      ApiDioClient.uri(
        Config.usesAdministration ? '/account' : '/users/$userId',
        host: Config.usesAdministration ? Config.administrationHost : host,
      ),
      options: _authenticatedOptions(accessToken: accessToken),
    );
  }

  Future<Response<dynamic>> getUserIdFromToken() {
    return _dio.getUri(
      ApiDioClient.uri('/users/get-id'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> getProfilePhoto(
    Object userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      ApiDioClient.uri(
        Config.usesAdministration
            ? '/users/$userId/profile-photo'
            : '/users/$userId/get-profile-photo',
        host: Config.usesAdministration ? Config.administrationHost : host,
      ),
      options: _authenticatedOptions(
        accessToken: accessToken,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> uploadProfilePhoto({
    required Object userId,
    required String photoBase64,
    required String format,
    String? accessToken,
    String? host,
  }) {
    return _dio.postUri(
      ApiDioClient.uri(
        Config.usesAdministration
            ? '/account/profile-photo'
            : '/users/$userId/upload-profile-photo',
        host: Config.usesAdministration ? Config.administrationHost : host,
      ),
      data: <String, dynamic>{'photoBase64': photoBase64, 'format': format},
      options: _authenticatedOptions(
        accessToken: accessToken,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> getUserByEmail(String email) {
    return _dio.getUri(
      ApiDioClient.uri('/users/$email'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> checkEmailExists(String email) {
    return _dio.getUri(
      ApiDioClient.uri(
        '/users/exists',
        queryParameters: <String, String>{'email': email},
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }
}
