import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/navigation/session_landing_preparation.dart';
import 'package:strnadi/recording/streamRec.dart';

Future<String?> captureActiveVerifiedSessionId() async {
  final ActivatedAuthSessionSnapshot? session =
      await activatedAuthSessions.capture();
  if (session?.verified != true) return null;

  try {
    final DateTime expirationDate =
        JwtDecoder.getExpirationDate(session!.accessToken);
    return expirationDate.isAfter(DateTime.now()) ? session.sessionId : null;
  } catch (_) {
    return null;
  }
}

Future<bool> hasActiveVerifiedSession() async {
  return await captureActiveVerifiedSessionId() != null;
}

Future<void> navigateToSessionLanding(BuildContext context) async {
  final bool isLoggedIn = await prepareSessionLanding(
    captureActiveVerifiedSessionId: captureActiveVerifiedSessionId,
    adoptGuestDrafts: DatabaseNew.updateRecordingsMail,
  );
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
