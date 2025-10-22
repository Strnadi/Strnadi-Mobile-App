/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/config.dart';

class _DialectColorCache {
  static const _prefsKey = 'dialect_colors_v1';
  static const Map<String, String> _defaults = {
    'BC': '#FDE441',
    'BE': '#52DC4D',
    'BD': '#666666',
    'BhBl': '#8ED0FF',
    'BlBh': '#4E68F0',
    'XB': '#F04D4D',
    'Neznámý': '#aaaaaa',
    'Bez dialektu': '#000000',
  };

  static Future<Map<String, String>> _readRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final Map<String, dynamic> parsed = jsonDecode(raw);
      return parsed.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeRaw(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  static Future<List<Color>> getColors(List<String> dialects) async {
    final raw = await _readRaw();
    final colors = <Color>[];

    // If cache is empty (first start offline), use defaults wholesale.
    final Map<String, String> source = raw.isEmpty ? _defaults : raw;

    for (final d in dialects) {
      final hex = source[d] ?? _defaults[d]; // fallback per-key if missing in cache
      if (hex == null) continue;
      try {
        colors.add(Color(int.parse(hex.replaceFirst('#', '0xff'))));
      } catch (_) {}
    }
    return colors;
  }
}



class DynamicIcon extends StatelessWidget {
  const DynamicIcon({
    super.key,
    required this.icon,
    this.dialects,
    this.iconSize = 24,
    this.padding = const EdgeInsets.all(8),
    this.cornerRadius = 6,
    this.backgroundColor,
    this.backgroundGradient,
    this.iconColor,
    this.iconGradient,
    this.border,
    this.shadow,
  });

  final IconData icon;
  final double iconSize;
  final EdgeInsets padding;
  final double cornerRadius;
  final List<String>? dialects;

  // Background fill (use either color or gradient; gradient wins if both set)
  final Color? backgroundColor;
  final Gradient? backgroundGradient;

  // Icon fill (use either color or gradient; gradient wins if both set)
  final Color? iconColor;
  final Gradient? iconGradient;

  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  /// Fetch all dialect colors from the server in a single request.
  /// Accepts either of these response shapes:
  /// 1) Map: { "BC": "#FDE441", ... }
  /// 2) List of objects: [ {"code":"BC","color":"#FDE441"}, ... ]
  static Future<Map<String, String>> _fetchAllDialectColors() async {
    final uri = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/dialects',
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch dialect colors: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final result = <String, String>{};

    if (data is Map) {
      // Map form: { "BC": "#FDE441", ... } or { "BC": {"color":"#FDE441"}, ... }
      data.forEach((k, v) {
        if (v is String) {
          result[k.toString()] = v;
        } else if (v is Map && v['color'] is String) {
          result[k.toString()] = v['color'] as String;
        }
      });
    } else if (data is List) {
      // List form: [ {"code":"BC","color":"#FDE441"}, ... ]
      for (final item in data) {
        if (item is Map) {
          final code = (item['code'] ?? item['dialect'] ?? item['dialect_code'])?.toString();
          final color = item['color']?.toString();
          if (code != null && color != null) {
            result[code] = color;
          }
        }
      }
    } else {
      logger.w('Unexpected /dialects response format: ${data.runtimeType}');
    }

    return result;
  }

  Future<List<Color>> _fetchDialectColors() async {
    if (dialects == null || dialects!.isEmpty) return [];
    try {
      // Read only from cache for offline usage. Do NOT fetch over network here.
      return await _DialectColorCache.getColors(dialects!);
    } catch (e) {
      logger.e('Failed to read cached dialect colors: $e');
      return [];
    }
  }
  /// Refresh (update) the cached dialect colors from the server in one call.
  /// Any provided [dialects] are ignored; the server response is authoritative.
  static Future<void> refreshDialects([List<String> dialects = const []]) async {
    try {
      final serverMap = await _fetchAllDialectColors();
      if (serverMap.isEmpty) {
        logger.w('refreshDialects: server returned empty map; keeping existing cache.');
        return;
      }
      await _DialectColorCache._writeRaw(serverMap);
    } catch (e) {
      logger.e('Failed to refresh dialect colors: $e');
    }
  }

  /// Convenience wrapper to refresh all dialect colors.
  static Future<void> refreshAllDialects() async {
    await refreshDialects();
  }

  /// Returns a map of dialect -> Color for legend display.
  /// Only includes dialects defined in the built-in defaults, but uses
  /// cached values when available; falls back to defaults for missing keys.
  static Future<Map<String, Color>> getLegendDialectColors() async {
    final raw = await _DialectColorCache._readRaw();
    final Map<String, String> source =
    raw.isEmpty ? _DialectColorCache._defaults : raw;

    final result = <String, Color>{};
    for (final key in _DialectColorCache._defaults.keys) {
      final hex = source[key] ?? _DialectColorCache._defaults[key];
      if (hex == null) continue;
      try {
        result[key] = Color(int.parse(hex.replaceFirst('#', '0xff')));
      } catch (_) {
        // ignore malformed entries
      }
    }
    return result;
  }

  static String _colorToHex6(Color c) {
    final rgb = c.value & 0x00FFFFFF; // drop alpha
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Future<List<Color>>? colorsFuture =
        (dialects != null && dialects!.isNotEmpty) ? _fetchDialectColors() : null;

    return FutureBuilder<List<Color>>(
      future: colorsFuture,
      builder: (context, snapshot) {
        // Start from explicitly provided background color/gradient as defaults
        Gradient? effBgGradient = backgroundGradient;
        Color? effBgColor = backgroundColor;

        // If dialect colors are available: 1 color -> solid fill; >1 -> gradient fill
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data!.isNotEmpty) {
          final colors = snapshot.data!;
          if (colors.length == 1) {
            effBgColor = colors.first;
            effBgGradient = null;
          } else {
            // Build a step (hard-stop) gradient: each segment keeps a solid color
            // by using duplicated stops at the segment boundaries.
            final hardColors = <Color>[];
            final stops = <double>[];
            final n = colors.length;
            for (var i = 0; i < n; i++) {
              final start = i / n;
              final end = (i + 1) / n;
              hardColors.add(colors[i]);
              stops.add(start);
              hardColors.add(colors[i]);
              stops.add(end);
            }

            effBgGradient = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hardColors,
              stops: stops,
              tileMode: TileMode.clamp,
            );
            effBgColor = null; // gradient drives the background
          }
        }

        // Square content area; we don't draw a glyph now (tile itself is the icon)
        Widget glyph = SizedBox.square(dimension: iconSize);

        return Container(
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: effBgGradient == null ? effBgColor : null,
            gradient: effBgGradient,
            borderRadius: BorderRadius.circular(cornerRadius),
            border: border ?? Border.all(color: Colors.black, width: 1),
            boxShadow: shadow,
          ),
          child: glyph,
        );
      },
    );
  }
}