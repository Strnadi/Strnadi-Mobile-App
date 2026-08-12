class ConnectedAccountsException implements Exception {
  const ConnectedAccountsException(this.message);

  final String message;

  @override
  String toString() => 'ConnectedAccountsException: $message';
}

class ConnectedAccountSession {
  const ConnectedAccountSession({
    required this.userId,
    required this.accessToken,
    required this.sessionId,
    required this.host,
    required this.verified,
  });

  final int userId;
  final String accessToken;
  final String sessionId;
  final String host;
  final bool verified;
}

enum ConnectedProviderState {
  connected,
  disconnected,
}

class ConnectedPlatformsStatus {
  const ConnectedPlatformsStatus({
    required this.apple,
    required this.google,
  });

  final ConnectedProviderState apple;
  final ConnectedProviderState google;
}

typedef CaptureConnectedAccountSession = Future<ConnectedAccountSession?>
    Function();
typedef CheckConnectedAccountSession = Future<bool> Function(
  ConnectedAccountSession session,
);
typedef ProviderStatusRequest = Future<int?> Function(
  ConnectedAccountSession session,
);

ConnectedProviderState classifyConnectedProviderStatus(int? statusCode) {
  switch (statusCode) {
    case 200:
      return ConnectedProviderState.connected;
    case 204:
    case 404:
      return ConnectedProviderState.disconnected;
    default:
      throw const ConnectedAccountsException(
        'The provider status could not be determined.',
      );
  }
}

class ConnectedPlatformsCoordinator {
  const ConnectedPlatformsCoordinator({
    required CaptureConnectedAccountSession captureSession,
    required CheckConnectedAccountSession isSessionCurrent,
  })  : _captureSession = captureSession,
        _isSessionCurrent = isSessionCurrent;

  final CaptureConnectedAccountSession _captureSession;
  final CheckConnectedAccountSession _isSessionCurrent;

  Future<ConnectedAccountSession> _requireSession() async {
    final ConnectedAccountSession? session = await _captureSession();
    if (session == null ||
        !session.verified ||
        session.userId <= 0 ||
        session.accessToken.trim().isEmpty ||
        session.sessionId.trim().isEmpty ||
        session.host.trim().isEmpty) {
      throw const ConnectedAccountsException(
        'A verified account session is required.',
      );
    }
    return session;
  }

  Future<ConnectedPlatformsStatus> load({
    required ProviderStatusRequest checkApple,
    required ProviderStatusRequest checkGoogle,
  }) async {
    final ConnectedAccountSession session = await _requireSession();
    final List<int?> statuses = await Future.wait<int?>(<Future<int?>>[
      checkApple(session),
      checkGoogle(session),
    ]);
    if (!await _isSessionCurrent(session)) {
      throw const ConnectedAccountsException(
        'The account session changed while loading provider status.',
      );
    }
    return ConnectedPlatformsStatus(
      apple: classifyConnectedProviderStatus(statuses[0]),
      google: classifyConnectedProviderStatus(statuses[1]),
    );
  }

  Future<bool> connect({
    required Future<int?> Function(ConnectedAccountSession session)
        connectProvider,
  }) async {
    final ConnectedAccountSession session = await _requireSession();
    final int? statusCode = await connectProvider(session);
    if (statusCode != 200) return false;
    return _isSessionCurrent(session);
  }
}
