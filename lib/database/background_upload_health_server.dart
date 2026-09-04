import 'dart:isolate';
import 'dart:ui';

/// Owns the isolate-name-server endpoint used by the UI to verify that a
/// recording upload worker is still alive.
class BackgroundRecordingHealthServer {
  final Map<int, ReceivePort> _ports = <int, ReceivePort>{};

  String portName(int recordingId) => '/upload/rec/$recordingId';

  bool start(int recordingId) {
    if (_ports.containsKey(recordingId)) {
      return false;
    }

    final ReceivePort candidate = ReceivePort();
    final bool registered = IsolateNameServer.registerPortWithName(
      candidate.sendPort,
      portName(recordingId),
    );
    if (!registered) {
      candidate.close();
      return false;
    }

    _ports[recordingId] = candidate;
    candidate.listen((Object? message) {
      try {
        if (message is SendPort) {
          message.send(<String, Object>{
            'status': 'uploading',
            'recordingId': recordingId,
          });
          return;
        }
        if (message is Map) {
          final Object? replyTo = message['replyTo'];
          if (replyTo is SendPort) {
            replyTo.send(<String, Object?>{
              'status': 'uploading',
              'recordingId': recordingId,
              'cmd': message['cmd'],
            });
          }
        }
      } catch (_) {
        // Health replies are best-effort and cannot affect an upload.
      }
    });
    return true;
  }

  void stop(int recordingId) {
    try {
      IsolateNameServer.removePortNameMapping(portName(recordingId));
    } catch (_) {
      // Best-effort cleanup for platform implementations without a mapping.
    }
    try {
      _ports.remove(recordingId)?.close();
    } catch (_) {
      // A closed receive port is already stopped.
    }
  }
}
