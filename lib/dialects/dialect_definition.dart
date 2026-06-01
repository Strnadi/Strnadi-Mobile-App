import 'dart:convert';

import 'package:strnadi/dialects/dialect_keyword_translator.dart';

const List<String> fallbackDialectHintCodes = <String>[
  'BC',
  'BE',
  'BhBl',
  'BlBh',
  'XB',
  'Other',
];

class DialectDefinition {
  const DialectDefinition({
    this.id,
    required this.rawCode,
    required this.code,
    this.color,
    required this.hintOrder,
  });

  final int? id;
  final String rawCode;
  final String code;
  final String? color;
  final int hintOrder;

  bool get isVisibleHint => hintOrder > 0 && code.trim().isNotEmpty;

  static DialectDefinition? fromJson(Map<dynamic, dynamic> json) {
    final rawCode = (json['dialectCode'] ??
            json['code'] ??
            json['dialect'] ??
            json['dialect_code'])
        ?.toString()
        .trim();
    if (rawCode == null || rawCode.isEmpty) return null;

    final canonicalCode =
        DialectKeywordTranslator.toEnglish(rawCode) ?? rawCode;
    final color = json['color']?.toString().trim();

    return DialectDefinition(
      id: _parseInt(json['id']),
      rawCode: rawCode,
      code: canonicalCode,
      color: color == null || color.isEmpty ? null : color,
      hintOrder: _parseInt(
            json['hintOrder'] ?? json['hint_order'] ?? json['order'],
          ) ??
          0,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

List<DialectDefinition> parseDialectDefinitions(dynamic payload) {
  final dynamic data = payload is String ? jsonDecode(payload) : payload;
  if (data is! List) return const <DialectDefinition>[];

  final definitions = <DialectDefinition>[];
  for (final item in data) {
    if (item is! Map) continue;
    final definition = DialectDefinition.fromJson(item);
    if (definition != null) {
      definitions.add(definition);
    }
  }
  return definitions;
}

List<DialectDefinition> visibleDialectHintDefinitions(dynamic payload) {
  return parseDialectDefinitions(payload)
      .where((definition) => definition.isVisibleHint)
      .toList(growable: false);
}

List<String> visibleDialectHintCodes(dynamic payload) {
  final codes = <String>[];
  final seen = <String>{};
  for (final definition in visibleDialectHintDefinitions(payload)) {
    if (seen.add(definition.code)) {
      codes.add(definition.code);
    }
  }
  return codes;
}
