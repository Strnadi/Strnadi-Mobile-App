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

  final Map<String, Color> dialectColors = {
    'BC': Colors.yellow,
    'BE': Colors.green,
    'BlBh': Colors.lightBlue,
    'BhBl': Colors.blue,
    'XB': Colors.red,
    'Jiné': Colors.white,
    'Nevím': Colors.grey.shade300,
    'Bez Dielektu': Colors.grey.shade300,
  };

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
                      Text(
                        'Přidání dialektu',
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
                          _dialectOption('Jiné'),
                        ],
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _dialectOption('Bez dialektu'),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _dialectOption('Nevím'),
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
                            ? () {
                          widget.onDialectAdded(DialectModel(
                            type: selectedDialect!,
                            label: selectedDialect!,
                            color: dialectColors[selectedDialect]!,
                            startTime: startTime,
                            endTime: endTime,
                          ));

                          Navigator.pop(context);
                        }
                            : null,
                        child: Text('Potvrdit'),
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
                        Image.asset(
                          'assets/dialects/$type.png',
                          width: 24,
                          height: 24,
                        ),
                        SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          type,
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
                  type,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    );
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