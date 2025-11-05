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

class DialectColorCache {
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
      final hex =
          source[d] ?? _defaults[d]; // fallback per-key if missing in cache
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
    this.showCenterDot = false,
    this.dotDiameter = 6,
    this.dotColor,
    this.cacheKey,
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

  final bool showCenterDot;
  final double dotDiameter;
  final Color? dotColor;

  final String? cacheKey; // unique rebuild key to avoid stale reuse across recordings

  static int getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.parse(hexColor, radix: 16);
  }

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
      throw Exception(
          'Failed to fetch dialect colors: HTTP ${response.statusCode}');
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
          final code = (item['code'] ?? item['dialect'] ?? item['dialect_code'])
              ?.toString();
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
      return await DialectColorCache.getColors(dialects!);
    } catch (e) {
      logger.e('Failed to read cached dialect colors: $e');
      return [];
    }
  }

  /// Refresh (update) the cached dialect colors from the server in one call.
  /// Any provided [dialects] are ignored; the server response is authoritative.
  static Future<void> refreshDialects(
      [List<String> dialects = const []]) async {
    try {
      final serverMap = await _fetchAllDialectColors();
      if (serverMap.isEmpty) {
        logger.w(
            'refreshDialects: server returned empty map; keeping existing cache.');
        return;
      }
      await DialectColorCache._writeRaw(serverMap);
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
    final raw = await DialectColorCache._readRaw();
    final Map<String, String> source =
        raw.isEmpty ? DialectColorCache._defaults : raw;

    final result = <String, Color>{};
    for (final key in DialectColorCache._defaults.keys) {
      final hex = source[key] ?? DialectColorCache._defaults[key];
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
        (dialects != null && dialects!.isNotEmpty)
            ? _fetchDialectColors()
            : null;

    return FutureBuilder<List<Color>>(
      key: ValueKey(cacheKey ?? (dialects ?? const <String>[]).join('+')),
      future: colorsFuture,
      builder: (context, snapshot) {
        // Start from explicitly provided background color/gradient as defaults
        Gradient? effBgGradient = backgroundGradient;
        Color? effBgColor = backgroundColor;

        bool useDiagonalSplit = false;
        List<Color> splitColors = const [];

        List<Color> _chooseColors() {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData && snapshot.data!.isNotEmpty) {
            return snapshot.data!;
          }
          // Fallback: derive colors synchronously from defaults while waiting
          final ds = (dialects ?? const <String>[]);
          final cols = <Color>[];
          for (final d in ds) {
            final hex = DialectColorCache._defaults[d];
            if (hex == null) continue;
            try {
              cols.add(Color(int.parse(hex.replaceFirst('#', '0xff'))));
            } catch (_) {}
          }
          return cols;
        }

        final colors = _chooseColors();
        if (colors.isNotEmpty) {
          if (colors.length == 1) {
            effBgColor = colors.first;
            effBgGradient = null;
          } else if (colors.length == 2) {
            useDiagonalSplit = true;
            splitColors = colors;
            effBgColor = null;
            effBgGradient = null;
          } else {
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
            effBgColor = null;
          }
        }

        // Square content area; we don't draw a glyph now (tile itself is the icon)
        Widget glyph = SizedBox.square(dimension: iconSize);

        // Optionally overlay a centered dot (e.g., to mark a special state)
        Widget content = glyph;
        if (showCenterDot) {
          content = Stack(
            alignment: Alignment.center,
            children: [
              glyph,
              Container(
                width: dotDiameter,
                height: dotDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor ?? Colors.black,
                ),
              ),
            ],
          );
        }

        // If exactly two dialects are present, paint a hard diagonal split (TL→BR)
        Widget paintedContent = content;
        if (useDiagonalSplit && splitColors.length == 2) {
          paintedContent = ClipRRect(
            borderRadius: BorderRadius.circular(cornerRadius),
            child: CustomPaint(
              painter: _DiagonalSplitPainter(splitColors[0], splitColors[1]),
              child: content,
            ),
          );
        }

        return Container(
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: useDiagonalSplit
                ? Colors.transparent
                : (effBgGradient == null ? effBgColor : null),
            gradient: useDiagonalSplit ? null : effBgGradient,
            borderRadius: BorderRadius.circular(cornerRadius),
            border: border ?? Border.all(color: Colors.black, width: 1),
            boxShadow: shadow,
          ),
          child: paintedContent,
        );
      },
    );
  }
}

class _DiagonalSplitPainter extends CustomPainter {
  final Color c1;
  final Color c2;
  _DiagonalSplitPainter(this.c1, this.c2);

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = c1;
    final p2 = Paint()..color = c2;

    // Triangle 1: top-left → top-right → bottom-left
    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, p1);

    // Triangle 2: bottom-right → bottom-left → top-right
    final path2 = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant _DiagonalSplitPainter oldDelegate) {
    return oldDelegate.c1 != c1 || oldDelegate.c2 != c2;
  }
}
