import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/audio/recording_audio_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(recordingSettingsChannel, null),
  );

  for (final value in <Object>[44100, '96000']) {
    test('uses native sample rate $value for mono PCM', () async {
      messenger.setMockMethodCallHandler(recordingSettingsChannel, (
        call,
      ) async {
        expect(call.method, 'getBestAudioSettings');
        return {'sampleRate': value};
      });
      final settings = await RecordingAudioSettings.load();
      expect(settings.sampleRate, int.parse(value.toString()));
      expect(settings.bitRate, settings.sampleRate * 16);
    });
  }

  for (final value in <Object?>[null, 0, -1, 'invalid']) {
    test('falls back to 48 kHz for invalid native rate $value', () async {
      messenger.setMockMethodCallHandler(
        recordingSettingsChannel,
        (call) async => {'sampleRate': value},
      );
      final settings = await RecordingAudioSettings.load();
      expect(settings.sampleRate, 48000);
      expect(settings.bitRate, 768000);
    });
  }

  test('missing native settings support keeps a usable PCM format', () async {
    messenger.setMockMethodCallHandler(
      recordingSettingsChannel,
      (call) async => throw MissingPluginException(),
    );
    final settings = await RecordingAudioSettings.load();
    expect(settings.sampleRate, 48000);
    expect(settings.bitRate, 768000);
  });
}
