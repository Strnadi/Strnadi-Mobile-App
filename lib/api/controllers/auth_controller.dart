import 'package:strnadi/projects/available_project.dart';
import 'dart:convert';
import 'dart:async';
import 'package:strnadi/api/api_logging.dart';
import 'package:strnadi/api/api_logger.dart';
import 'package:strnadi/logging/log_failure.dart';
import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

/// Injectable API boundary; endpoint payloads belong here, not in session state.
abstract class OAuthApi {
  const OAuthApi();
  Future<Map<String, dynamic>> postForm(
    Uri endpoint,
    Map<String, String> fields,
  );

  Future<dynamic> getAdministration(Uri endpoint, String token) =>
      throw UnimplementedError('Administration discovery is not implemented');

  Future<dynamic> postAdministration(
    Uri endpoint,
    String token,
    Map<String, dynamic> body,
  ) => throw UnimplementedError('Administration mutation is not implemented');

  Future<List<AvailableProject>> projectCatalog(
    OAuthConfiguration configuration,
    String token,
  ) async {
    final body = await getAdministration(
      configuration.issuer.resolve('/projects'),
      token,
    );
    if (body is! List) throw const FormatException('Invalid projects response');
    return body
        .map(
          (item) =>
              AvailableProject.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> joinProject(
    OAuthConfiguration configuration,
    String token,
    String subject,
    AvailableProject project, {
    void Function()? requireCurrent,
  }) async {
    project.configuration(
      configuration,
    ); // Validate destination metadata first.
    final profile = await getAdministration(
      configuration.issuer.resolve('/account/profile'),
      token,
    );
    if (profile is! Map ||
        profile['id'] != subject ||
        profile['email'] is! String ||
        (profile['email'] as String).trim().isEmpty) {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
    requireCurrent?.call();
    final member = await postAdministration(
      configuration.issuer.resolve('/projects/${project.id}/members'),
      token,
      {'email': profile['email']},
    );
    if (member is! Map || member['userId'] != subject) {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
  }

  Future<List<AvailableProject>> availableProjects(
    OAuthConfiguration configuration,
    String token,
    String subject,
  ) async {
    final body = await getAdministration(
      configuration.issuer.resolve('/users/$subject/projects'),
      token,
    );
    if (body is! List) throw const FormatException('Invalid projects response');
    return body
        .map(
          (item) =>
              AvailableProject.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Uri logoutUri(OAuthConfiguration configuration) =>
      configuration.logoutEndpoint.replace(
        queryParameters: {'redirect_uri': OAuthConfiguration.redirectUri},
      );

  Future<Map<String, dynamic>> exchangeAuthorizationCode(
    OAuthConfiguration configuration, {
    required String code,
    required String verifier,
  }) => postForm(configuration.tokenEndpoint, {
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': OAuthConfiguration.redirectUri,
    'client_id': OAuthConfiguration.clientId,
    'code_verifier': verifier,
  });

  Future<Map<String, dynamic>> refreshAdministrationToken(
    OAuthConfiguration configuration,
    String refreshToken,
  ) => postForm(configuration.tokenEndpoint, {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': OAuthConfiguration.clientId,
  });

  Future<Map<String, dynamic>> exchangeProjectToken(
    OAuthConfiguration configuration,
    String administrationToken,
  ) => postForm(configuration.tokenEndpoint, {
    'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
    'subject_token': administrationToken,
    'subject_token_type': 'urn:ietf:params:oauth:token-type:access_token',
    'client_id': OAuthConfiguration.clientId,
    'project_id': configuration.projectId,
  });
}

class AuthController extends OAuthApi {
  const AuthController();

  @override
  Future<dynamic> getAdministration(Uri endpoint, String token) async {
    final response = await ApiDioClient.authorization.getUri<dynamic>(
      endpoint,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        followRedirects: false,
        maxRedirects: 0,
        extra: const {'authRequired': false},
      ),
    );
    if (response.statusCode != 200) {
      throw OAuthFailure(
        response.statusCode == 401 || response.statusCode == 403
            ? OAuthFailureKind.exchangeDenied
            : OAuthFailureKind.server,
      );
    }
    return response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
  }

  @override
  Future<dynamic> postAdministration(
    Uri endpoint,
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await ApiDioClient.authorization.postUri<dynamic>(
      endpoint,
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Authorization': 'Bearer $token'},
        followRedirects: false,
        maxRedirects: 0,
        extra: const {'authRequired': false},
      ),
    );
    if (response.statusCode != 201) {
      throw OAuthFailure(
        response.statusCode == 401 || response.statusCode == 403
            ? OAuthFailureKind.exchangeDenied
            : OAuthFailureKind.server,
      );
    }
    return response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
  }

  @override
  Future<Map<String, dynamic>> postForm(
    Uri endpoint,
    Map<String, String> fields,
  ) async {
    Response<dynamic>? completedResponse;
    try {
      final response = await ApiDioClient.authorization
          .postUri<dynamic>(
            endpoint,
            data: fields,
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              responseType: ResponseType.plain,
              followRedirects: false,
              maxRedirects: 0,
              extra: const {'authRequired': false},
            ),
          )
          .timeout(const Duration(seconds: 30));
      completedResponse = response;
      if (response.statusCode != 200 &&
          ![400, 401, 403].contains(response.statusCode)) {
        throw OAuthFailure(
          OAuthFailureKind.server,
          logFailure: apiFailureForResponse(
            response,
            reason: response.statusCode != null && response.statusCode! < 400
                ? 'OAuth token endpoint returned an unexpected HTTP response'
                : null,
          ),
        );
      }
      if (response.statusCode != 200) {
        String? oauthError;
        try {
          final body = jsonDecode(response.data as String);
          if (body is Map && body['error'] is String) {
            oauthError = body['error'];
          }
        } on FormatException {
          // Never include an unexpected response body in the error.
        }
        if (oauthError == 'temporarily_unavailable' ||
            oauthError == 'server_error' ||
            (response.statusCode == 400 &&
                ![
                  'invalid_grant',
                  'invalid_token',
                  'access_denied',
                ].contains(oauthError))) {
          throw OAuthFailure(
            OAuthFailureKind.server,
            logFailure: apiFailureForResponse(response),
          );
        }
        final kind = fields['grant_type'] == 'refresh_token'
            ? OAuthFailureKind.loginRequired
            : fields['grant_type'] ==
                  'urn:ietf:params:oauth:grant-type:token-exchange'
            ? OAuthFailureKind.exchangeDenied
            : OAuthFailureKind.denied;
        throw OAuthFailure(kind, logFailure: apiFailureForResponse(response));
      }
      final body = jsonDecode(response.data as String);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('OAuth response is not an object.');
      }
      return body;
    } on OAuthFailure catch (error, stackTrace) {
      // HTTP errors are already observed by Dio. A non-error HTTP status can
      // still violate the token endpoint contract, and the UI only shows its
      // translated category, so report that protocol failure here.
      final status = error.logFailure?.api?.statusCode;
      if (status != null && status < 400) {
        apiLogger.e(
          'OAuth token response was rejected.',
          error: error,
          stackTrace: stackTrace,
          failure: error.logFailure,
        );
      }
      rethrow;
    } on FormatException catch (error, stackTrace) {
      final failure = completedResponse == null
          ? AppFailure(
              reason: 'OAuth response could not be decoded',
              error: error,
              stackTrace: stackTrace,
            )
          : apiFailureForResponse(
              completedResponse,
              reason: 'OAuth response could not be decoded',
              stackTrace: stackTrace,
            );
      apiLogger.e(
        'OAuth returned an invalid response.',
        error: error,
        stackTrace: stackTrace,
        failure: failure,
      );
      Error.throwWithStackTrace(
        OAuthFailure(OAuthFailureKind.invalidResponse, logFailure: failure),
        stackTrace,
      );
    } catch (error, stackTrace) {
      final alreadyObserved =
          error is DioException && AppFailureRegistry.lookup(error) != null;
      final failure = error is DioException
          ? apiFailureForDioError(error, stackTrace: stackTrace)
          : AppFailure(
              reason: 'OAuth request did not complete',
              expected: error is TimeoutException,
              error: error,
              stackTrace: stackTrace,
            );
      if (!alreadyObserved) {
        apiLogger.w(
          'OAuth request failed.',
          error: error,
          stackTrace: stackTrace,
          failure: failure,
        );
      }
      Error.throwWithStackTrace(
        OAuthFailure(OAuthFailureKind.network, logFailure: failure),
        stackTrace,
      );
    }
  }

  Dio get _dio => ApiDioClient.instance;

  Future<Response<dynamic>> login({
    required String email,
    required String password,
  }) {
    return _dio.postUri(
      ApiDioClient.uri('/auth/login'),
      data: <String, String>{'email': email, 'password': password},
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> verifyJwt(String token) {
    return _dio.getUri(
      ApiDioClient.uri('/auth/verify-jwt'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> renewJwt(String token) {
    return _dio.getUri(
      ApiDioClient.uri('/auth/renew-jwt'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> hasGoogleId(
    Object userId, {
    required String accessToken,
    required String host,
  }) {
    if (Config.usesAdministration) {
      return _dio
          .getUri(
            ApiDioClient.uri(
              '/account/external-logins',
              host: Config.administrationHost,
            ),
            options: Options(
              headers: {'Authorization': 'Bearer $accessToken'},
              followRedirects: false,
              extra: const {'authRequired': true},
            ),
          )
          .then((response) {
            if (response.statusCode == 200 && response.data is List) {
              response.data = (response.data as List).contains('Google');
            }
            return response;
          });
    }
    return _dio.getUri(
      ApiDioClient.uri(
        '/auth/has-google-id',
        host: host,
        queryParameters: <String, Object>{'userId': userId},
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, String>{'Authorization': 'Bearer $accessToken'},
        extra: const <String, Object>{'authRequired': true},
      ),
    );
  }

  Future<Response<dynamic>> hasAppleId(
    Object userId, {
    required String accessToken,
    required String host,
  }) {
    if (Config.usesAdministration) {
      return _dio
          .getUri(
            ApiDioClient.uri(
              '/account/external-logins',
              host: Config.administrationHost,
            ),
            options: Options(
              headers: {'Authorization': 'Bearer $accessToken'},
              followRedirects: false,
              extra: const {'authRequired': true},
            ),
          )
          .then((response) {
            if (response.statusCode == 200 && response.data is List) {
              response.data = (response.data as List).contains('Apple');
            }
            return response;
          });
    }
    return _dio.getUri(
      ApiDioClient.uri(
        '/auth/has-apple-id',
        host: host,
        queryParameters: <String, Object>{'userId': userId},
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, String>{'Authorization': 'Bearer $accessToken'},
        extra: const <String, Object>{'authRequired': true},
      ),
    );
  }

  Future<Response<dynamic>> resendVerificationEmail({
    required Object userId,
    required String token,
  }) {
    return _dio.getUri(
      ApiDioClient.uri('/auth/$userId/resend-verify-email'),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> requestPasswordReset(String email) {
    if (Config.hostEnvironment == HostEnvironment.preprod) {
      return _dio.postUri(
        ApiDioClient.uri(
          '/account/forgot-password',
          host: Config.administrationHost,
        ),
        data: <String, String>{'email': email},
        options: Options(
          contentType: Headers.jsonContentType,
          followRedirects: false,
          extra: const <String, Object>{'authRequired': false},
        ),
      );
    }
    return _dio.getUri(
      ApiDioClient.uri('/auth/$email/reset-password'),
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> setResetPassword({
    required String email,
    required String token,
    required String password,
  }) {
    if (Config.usesAdministration) {
      throw UnsupportedError(
        'Complete the password reset using the browser link in the email.',
      );
    }
    return _dio.patchUri(
      ApiDioClient.uri('/auth/$email/reset-password'),
      data: <String, String>{'password': password},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> signUp({
    required Map<String, dynamic> body,
    String? token,
  }) {
    return _dio.postUri(
      ApiDioClient.uri('/auth/sign-up'),
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> appleSignIn({
    required Map<String, dynamic> body,
    String? token,
  }) {
    return _dio.postUri(
      ApiDioClient.uri('/auth/apple'),
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> googleSignIn({
    required String idToken,
    String? email,
    String? token,
  }) {
    final data = <String, String>{'idToken': idToken};
    if (email != null && email.isNotEmpty) {
      data['email'] = email;
    }
    return _dio.postUri(
      ApiDioClient.uri('/auth/google'),
      data: data,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'},
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> loginGoogle({required String idToken}) {
    return _dio.postUri(
      ApiDioClient.uri('/auth/login-google'),
      data: <String, String>{'idToken': idToken},
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }

  Future<Response<dynamic>> signUpGoogle({
    required String idToken,
    String? email,
  }) {
    final data = <String, String>{'idToken': idToken};
    if (email != null && email.isNotEmpty) {
      data['email'] = email;
    }
    return _dio.postUri(
      ApiDioClient.uri('/auth/sign-up-google'),
      data: data,
      options: Options(
        contentType: Headers.jsonContentType,
        extra: const <String, Object>{'authRequired': false},
      ),
    );
  }
}
