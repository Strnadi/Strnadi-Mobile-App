import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:strnadi/config/oauth_configuration.dart';

enum OAuthFailureKind {
  cancelled,
  denied,
  invalidCallback,
  staleSession,
  network,
  server,
  invalidResponse,
  loginRequired,
  exchangeDenied,
}

/// Carries only a fixed category: server responses, codes, tokens and browser
/// URLs must never leak through an exception's string representation.
class OAuthFailure implements Exception {
  const OAuthFailure(this.kind);
  final OAuthFailureKind kind;
  String get translationKey => 'auth.administration.errors.${kind.name}';
  @override
  String toString() => 'OAuthFailure(${kind.name})';
}

class PkceAttempt {
  PkceAttempt._(this.verifier, this.state);

  factory PkceAttempt.create() {
    final random = Random.secure();
    String entropy() =>
        _base64Url(List<int>.generate(32, (_) => random.nextInt(256)));
    return PkceAttempt._(entropy(), entropy());
  }

  final String verifier;
  final String state;
  bool _consumed = false;

  static String challengeFor(String verifier) =>
      _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

  Uri authorizationUri(OAuthConfiguration config) =>
      config.authorizeEndpoint.replace(queryParameters: {
        'client_id': OAuthConfiguration.clientId,
        'redirect_uri': OAuthConfiguration.redirectUri,
        'response_type': 'code',
        'code_challenge': challengeFor(verifier),
        'code_challenge_method': 'S256',
        'state': state,
        if (config.scopes.isNotEmpty) 'scope': config.scopes.join(' '),
      });

  void cancel() => _consumed = true;

  String consumeCallback(String callback) {
    if (_consumed) {
      throw const OAuthFailure(OAuthFailureKind.invalidCallback);
    }
    // Even a malformed callback ends this attempt. Retrying requires fresh
    // entropy, and a duplicate callback can never exchange a second code.
    _consumed = true;
    try {
      final uri = Uri.parse(callback);
      final parameters = uri.queryParametersAll;
      if (uri.scheme != 'com.delta.strnadi' ||
          uri.host != 'auth' ||
          uri.path != '/callback' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          callback.split('?').first != OAuthConfiguration.redirectUri ||
          parameters['state']?.length != 1 ||
          parameters['state']!.single != state) {
        throw const OAuthFailure(OAuthFailureKind.invalidCallback);
      }
      if (parameters.containsKey('error')) {
        if (parameters['error']?.length != 1 ||
            parameters.containsKey('code')) {
          throw const OAuthFailure(OAuthFailureKind.invalidCallback);
        }
        throw const OAuthFailure(OAuthFailureKind.denied);
      }
      if (parameters['code']?.length != 1 ||
          parameters['code']!.single.trim().isEmpty) {
        throw const OAuthFailure(OAuthFailureKind.invalidCallback);
      }
      return parameters['code']!.single;
    } on FormatException {
      throw const OAuthFailure(OAuthFailureKind.invalidCallback);
    }
  }
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
