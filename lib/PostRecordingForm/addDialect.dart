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

import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';

class DialectModel {
  final String type;
  final String label;
  final Color color;
  final double startTime;
  final double endTime;

  DialectModel({
    required this.type,
    required this.label,
    required this.color,
    required this.startTime,
    required this.endTime,
  });
}

class DialectSelectionDialog extends StatefulWidget {
  final double? currentPosition;
  final double duration;
  final Function(DialectModel?) onDialectAdded;
  Widget? spectogram;

  DialectSelectionDialog({
    Key? key,
    this.spectogram,
    this.currentPosition,
    required this.duration,
    required this.onDialectAdded,
  }) : super(key: key);

  @override
  _DialectSelectionDialogState createState() => _DialectSelectionDialogState();
}

class _DialectSelectionDialogState extends State<DialectSelectionDialog> {
  String? selectedDialect;
  late double startTime;
  late double endTime;

  // Fallback colors for non-dialect options, dialects resolved from cache/defaults.
  final Map<String, Color> specialTypeColors = {
    'Other': Colors.white,
    "I don't know": Colors.grey,
    'No Dialect': Colors.black,
  };

  static const String _prefsKey = 'dialect_colors_v1';
  static const Map<String, String> _defaults = {
    'BC': '#FDE441',
    'BE': '#52DC4D',
    'BD': '#666666',
    'BhBl': '#8ED0FF',
    'BlBh': '#4E68F0',
    'XB': '#F04D4D',
    'Unknown': '#aaaaaa',
    'No Dialect': '#000000',
  };

  Color _hexToColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xff')));
  }

  Future<Color> _resolveDialectColor(String type) async {
    // Non-dialect special options
    final canonical = DialectKeywordTranslator.toEnglish(type) ?? type;
    if (specialTypeColors.containsKey(canonical)) {
      return specialTypeColors[canonical]!;
    }

    // Dialect color from cache, with defaults fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> parsed = jsonDecode(raw);
        final String? hex =
            parsed[canonical] as String? ?? parsed[type] as String?;
        if (hex != null) return _hexToColor(hex);
      }
    } catch (_) {}

    // Fallback to internal defaults
    final hex = _defaults[canonical] ?? _defaults[type];
    if (hex != null) return _hexToColor(hex);

    // Last resort
    return Colors.grey;
  }

  @override
  void initState() {
    super.initState();
    if (widget.currentPosition == null) {
      startTime = 0.0;
      endTime = 3.0;
    } else {
      startTime = widget.currentPosition!;
      endTime = (widget.currentPosition! + 3.0).clamp(0.0, widget.duration);
    }
  }


  String _formatDuration(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        widget.onDialectAdded(null);
        Navigator.pop(context);
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t('postRecordingForm.addDialect.title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24),
                      // Spectogram with overlay markers
                      if (widget.spectogram != null) SizedBox(
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Spectrogram background
                            widget.spectogram!,
                          ],
                        ),
                      ),
                      // Playback controls row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.replay_10),
                            onPressed: () {
                              // Handle rewind
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow),
                            iconSize: 32,
                            onPressed: () {
                              // Handle play
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.forward_10),
                            onPressed: () {
                              // Handle forward
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      // Dialect options arranged in a grid
                      GridView.count(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 2.5,
                        children: [
                          _dialectOption('BC'),
                          _dialectOption('BE'),
                          _dialectOption('BlBh'),
                          _dialectOption('BhBl'),
                          _dialectOption('XB'),
                          _dialectOption('Other'),
                        ],
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _dialectOption('No Dialect'),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _dialectOption("I don't know"),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFCDC4D),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: selectedDialect != null
                            ? () async {
                                final color = await _resolveDialectColor(selectedDialect!);
                                final canonical = DialectKeywordTranslator
                                        .toEnglish(selectedDialect!) ??
                                    selectedDialect!;
                                final displayLabel =
                                    _displayLabelForType(canonical);
                                widget.onDialectAdded(DialectModel(
                                  type: canonical,
                                  label: displayLabel,
                                  color: color,
                                  startTime: startTime,
                                  endTime: endTime,
                                ));
                                if (mounted) Navigator.pop(context);
                              }
                            : null,
                        child: Text(t('postRecordingForm.addDialect.confirm')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  widget.onDialectAdded(null);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarker(Color color) {
    return Container(
      height: 40,
      width: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _dialectOption(String type) {
    bool isSelected = selectedDialect == type;
    // Only these are real dialects with icon assets
    const List<String> dialectTypes = ['BC', 'BE', 'BlBh', 'BhBl', 'XB'];
    bool isDialect = dialectTypes.contains(type);
    final displayLabel = _displayLabelForType(type);

    return InkWell(
      onTap: () {
        setState(() {
          selectedDialect = type;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFF5F5F5) : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: isDialect
            ? LayoutBuilder(
                builder: (context, constraints) {
                  // Show the dialect logo only when the tile is wide enough.
                  const double minWidthForLogo = 100;
                  final bool showLogo = constraints.maxWidth >= minWidthForLogo;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (showLogo) ...[
                        DynamicIcon(
                          icon: Icons.circle,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.transparent,
                          dialects: [type],
                        ),
                        SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      Image.asset(
                        'assets/dialects/spect/$type.png',
                        width: 35,
                        height: 15,
                        fit: BoxFit.contain,
                      ),
                    ],
                  );
                },
              )
            : Center(
                child: Text(
                  displayLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    );
  }

  String _displayLabelForType(String type) {
    const List<String> dialectTypes = ['BC', 'BE', 'BlBh', 'BhBl', 'XB'];
    final canonical = DialectKeywordTranslator.toEnglish(type) ?? type;
    if (dialectTypes.contains(canonical)) return canonical;
    return DialectKeywordTranslator.toLocalized(canonical);
  }
}

// Custom track shape to make the slider cover the full area
class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
