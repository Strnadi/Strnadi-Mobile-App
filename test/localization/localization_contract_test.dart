import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _flattenTranslations(
  Map<String, dynamic> map, [
  String prefix = '',
]) {
  final result = <String, String>{};
  for (final entry in map.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      result.addAll(_flattenTranslations(value, key));
    } else {
      result[key] = value.toString();
    }
  }
  return result;
}

Map<String, String> _readLocale(String language) {
  final json = jsonDecode(
    File('assets/lang/$language.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return _flattenTranslations(json);
}

Set<String> _placeholders(String value) => RegExp(r'\{[^}]+\}')
    .allMatches(value)
    .map((match) => match.group(0)!)
    .toSet();

void main() {
  const languages = <String>['cs', 'en', 'de'];
  late Map<String, Map<String, String>> translations;

  setUpAll(() {
    translations = {
      for (final language in languages) language: _readLocale(language),
    };
  });

  test('all supported locales expose the same scalar translation keys', () {
    final referenceKeys = translations['en']!.keys.toSet();

    for (final language in languages) {
      expect(
        translations[language]!.keys.toSet(),
        referenceKeys,
        reason: '$language must not fall back to raw localization keys',
      );
    }
  });

  test('recording UI and background upload messages are fully localized', () {
    const requiredKeys = <String>{
      'streamRec.errors.micPermission',
      'streamRec.errors.locationPermission',
      'streamRec.errors.noRecordingFound',
      'streamRec.buttons.startRecording',
      'streamRec.buttons.pauseRecording',
      'streamRec.buttons.resumeRecording',
      'postRecordingForm.recordingForm.slider.oneBird',
      'postRecordingForm.recordingForm.slider.twoBirds',
      'postRecordingForm.recordingForm.slider.threeOrMoreBirds',
      'notifications.recordingUpload.failure.title',
      'notifications.recordingUpload.failure.missingId',
      'notifications.recordingUpload.failure.databaseRead',
      'notifications.recordingUpload.failure.upload',
      'notifications.recordingUpload.notFound.title',
      'notifications.recordingUpload.notFound.message',
      'notifications.recordingUpload.success.title',
      'notifications.recordingUpload.success.message',
      'dialogs.googlePlayServicesRequired',
      'dialogs.startupPermissionsRequired',
      'updates.available.messageWithoutVersion',
    };

    for (final language in languages) {
      final locale = translations[language]!;
      for (final key in requiredKeys) {
        expect(locale[key], isNotNull, reason: '$language is missing $key');
        expect(locale[key], isNotEmpty, reason: '$language has an empty $key');
        expect(locale[key], isNot(key),
            reason: '$language exposes raw key $key');
        expect(
          _placeholders(locale[key]!),
          _placeholders(translations['en']![key]!),
          reason: '$language placeholders differ for $key',
        );
      }
    }
  });

  test('recording surfaces reference keys instead of user-facing literals', () {
    final streamRec = File('lib/recording/streamRec.dart').readAsStringSync();
    final recordingForm =
        File('lib/PostRecordingForm/RecordingForm.dart').readAsStringSync();
    final callback = File('lib/callback_dispatcher.dart').readAsStringSync();

    expect(
      streamRec,
      isNot(contains(
        'Pro správné fungování aplikace je potřeba povolit mikrofon',
      )),
    );
    expect(
      streamRec,
      isNot(contains(
        'Pro zahájení nahrávání musíte povolit přístup k poloze',
      )),
    );
    expect(
      streamRec,
      contains("t('streamRec.buttons.startRecording')"),
    );
    expect(
      streamRec,
      contains("t('streamRec.buttons.pauseRecording')"),
    );
    expect(
      streamRec,
      contains("t('streamRec.buttons.resumeRecording')"),
    );

    expect(
      recordingForm,
      contains('postRecordingForm.recordingForm.slider.oneBird'),
    );
    expect(
      recordingForm,
      contains('postRecordingForm.recordingForm.slider.twoBirds'),
    );
    expect(recordingForm, isNot(contains(' strnad')));

    expect(callback, contains('await _loadBackgroundLocalization();'));
    expect(callback, contains('await preferences.reload();'));
    expect(callback, contains("Localization.load('assets/lang/en.json')"));
    expect(
      callback,
      contains("t('notifications.recordingUpload.failure.title')"),
    );
    expect(
      callback,
      isNot(contains(".replaceFirst('{error}', e.toString())")),
    );
    expect(callback, isNot(contains("'Nahrávání nahrávky selhalo'")));
    expect(callback, isNot(contains("'Recording Not Found'")));

    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("t('dialogs.googlePlayServicesRequired')"));
    expect(main, contains("t('dialogs.startupPermissionsRequired')"));
    expect(
      main,
      isNot(contains(
        "t('Aplikace potřebuje povolení k mikrofonu a notifikacím.",
      )),
    );
  });

  test('active Dart sources use only defined stable literal translation keys',
      () {
    final RegExp literalTranslation = RegExp(
      r'''(?<![A-Za-z0-9_.])t\(\s*(?:'([^']*)'|"([^"]*)")''',
    );
    final RegExp stableDottedKey =
        RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$');
    final Map<String, String> english = translations['en']!;
    final List<String> failures = <String>[];

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains(
              '${Platform.pathSeparator}archived${Platform.pathSeparator}') ||
          entity.path.contains(
              '${Platform.pathSeparator}database${Platform.pathSeparator}archive${Platform.pathSeparator}')) {
        continue;
      }

      final String activeSource = entity
          .readAsLinesSync()
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final RegExpMatch match
          in literalTranslation.allMatches(activeSource)) {
        final String key = match.group(1) ?? match.group(2) ?? '';
        if (!stableDottedKey.hasMatch(key)) {
          failures.add('${entity.path}: invalid literal key "$key"');
          continue;
        }
        if (!english.containsKey(key)) {
          failures.add('${entity.path}: undefined translation key "$key"');
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
