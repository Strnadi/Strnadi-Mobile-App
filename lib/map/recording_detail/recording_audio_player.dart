import 'package:just_audio/just_audio.dart';

/// Audio boundary for the detail controller, allowing plugin-free tests.
abstract interface class RecordingAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Duration? get duration;
  bool get playing;
  Future<void> setFilePath(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class JustAudioRecordingPlayer implements RecordingAudioPlayer {
  JustAudioRecordingPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Duration? get duration => _player.duration;
  @override
  bool get playing => _player.playing;
  @override
  Future<void> setFilePath(String path) async => _player.setFilePath(path);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> dispose() => _player.dispose();
}
