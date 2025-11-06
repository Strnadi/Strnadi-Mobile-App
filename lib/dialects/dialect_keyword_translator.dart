/*
 * Copyright (C) 2025
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:strnadi/localization/localization.dart';

/// Handles conversion of human-readable dialect keywords between the
/// user-facing locale and the canonical English form that is persisted
/// locally and sent to the backend.
class DialectKeywordTranslator {
  static const List<_DialectKeywordEntry> _entries = [
    _DialectKeywordEntry(
      english: 'Unknown',
      translationKey: 'dialectKeywords.unknown',
      synonyms: [
        'Unknown',
        'Neznámý',
        'Neznamy',
        'Neznámy',
        'Neznámá',
        'Neznáme',
        'Neznámé',
        'Unbekannt',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Unknown dialect',
      translationKey: 'dialectKeywords.unknownDialect',
      synonyms: [
        'Unknown dialect',
        'Neznámý dialekt',
        'Unbekannter Dialekt',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Undetermined',
      translationKey: 'dialectKeywords.undetermined',
      synonyms: [
        'Undetermined',
        'Undetermined dialect',
        'Neurceno',
        'Neurčeno',
        'Neurčené',
        'Neurčená',
        'Unbestimmt',
      ],
    ),
    _DialectKeywordEntry(
      english: 'No Dialect',
      translationKey: 'dialectKeywords.noDialect',
      synonyms: [
        'No Dialect',
        'Without dialect',
        'Without Dialect',
        'Bez dialektu',
        'Ohne Dialekt',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Other',
      translationKey: 'dialectKeywords.other',
      synonyms: [
        'Other',
        'Jiné',
        'Jine',
        'Jiný',
        'Andere',
      ],
    ),
    _DialectKeywordEntry(
      english: "I don't know",
      translationKey: 'dialectKeywords.iDontKnow',
      synonyms: [
        "I don't know",
        "I dont know",
        "I don’t know",
        'Nevím',
        'Nevim',
        'Ich weiß es nicht',
        'Ich weiss es nicht',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Rare',
      translationKey: 'dialectKeywords.rare',
      synonyms: [
        'Rare',
        'Vzácné',
        'Vzácná',
        'Vzacne',
        'Selten',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Transitional',
      translationKey: 'dialectKeywords.transitional',
      synonyms: [
        'Transitional',
        'Přechodný',
        'Prechodny',
        'Přechodná',
        'Přechodné',
        'Übergang',
        'Uebergang',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Mix',
      translationKey: 'dialectKeywords.mix',
      synonyms: [
        'Mix',
        'Mischung',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Atypical',
      translationKey: 'dialectKeywords.atypical',
      synonyms: [
        'Atypical',
        'Atypický',
        'Atypicky',
        'Atypická',
        'Atypické',
        'Atypisch',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Unfinished',
      translationKey: 'dialectKeywords.unfinished',
      synonyms: [
        'Unfinished',
        'Nedokončený',
        'Nedokonceny',
        'Nedokončená',
        'Nedokončené',
        'Unvollständig',
        'Unvollstaendig',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Unassessed',
      translationKey: 'dialectKeywords.unassessed',
      synonyms: [
        'Unassessed',
        'Nevyhodnoceno',
        'Nevyhodnocená',
        'Nevyhodnocené',
        'Nicht bewertet',
      ],
    ),
    _DialectKeywordEntry(
      english: 'Unusable',
      translationKey: 'dialectKeywords.unusable',
      synonyms: [
        'Unusable',
        'Nepoužitelný',
        'Nepouzitelny',
        'Nepoužitelná',
        'Nepoužitelné',
        'Unbrauchbar',
      ],
    ),
  ];

  static final Map<String, _DialectKeywordEntry> _synonymIndex = {
    for (final entry in _entries)
      for (final synonym in entry.synonyms)
        _normalize(synonym): entry,
  };

  static final Map<String, _DialectKeywordEntry> _englishIndex = {
    for (final entry in _entries) _normalize(entry.english): entry,
  };

  /// Converts [value] into its canonical English form if it matches
  /// a known keyword. Returns the trimmed input otherwise.
  static String? toEnglish(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final normalized = _normalize(trimmed);
    final entry = _synonymIndex[normalized];
    return entry?.english ?? trimmed;
  }

  /// Converts a canonical English [value] to the currently selected locale.
  /// When [value] is not recognized, it is returned unchanged.
  static String toLocalized(String value) {
    final english = toEnglish(value) ?? value;
    final entry = _englishIndex[_normalize(english)];
    if (entry == null) return english;
    return t(entry.translationKey);
  }

  /// Converts a list of dialect keywords to their canonical English forms.
  static List<String> toEnglishList(Iterable<String> values) {
    return values.map((v) => toEnglish(v) ?? v).toList();
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}

class _DialectKeywordEntry {
  final String english;
  final String translationKey;
  final List<String> synonyms;

  const _DialectKeywordEntry({
    required this.english,
    required this.translationKey,
    required this.synonyms,
  });
}
