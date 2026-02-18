import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:strnadi/recording/streamRec.dart';

Future<bool> hasActiveVerifiedSession() async {
  const secureStorage = FlutterSecureStorage();
  final String? token = await secureStorage.read(key: 'token');
  final String? verified = await secureStorage.read(key: 'verified');

  if (token == null || token.isEmpty || verified != 'true') {
    return false;
  }

  try {
    final DateTime expirationDate = JwtDecoder.getExpirationDate(token);
    return expirationDate.isAfter(DateTime.now());
  } catch (_) {
    return false;
  }
}

Future<void> navigateToSessionLanding(BuildContext context) async {
  final bool isLoggedIn = await hasActiveVerifiedSession();
  if (!context.mounted) return;

  if (isLoggedIn) {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LiveRec(),
        settings: const RouteSettings(name: '/Recorder'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
    return;
  }

  Navigator.pushNamedAndRemoveUntil(
    context,
    '/authorizator',
    (Route<dynamic> route) => false,
  );
}
