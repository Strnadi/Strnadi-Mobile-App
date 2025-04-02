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
  final double currentPosition;
  final double duration;
  final Function(DialectModel) onDialectAdded;
  Widget? spectogram;

  DialectSelectionDialog({
    Key? key,
    required this.spectogram,
    required this.currentPosition,
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
    'BiBh': Colors.lightBlue,
    'BhBi': Colors.blue,
    'XB': Colors.red,
    'Jiné': Colors.white,
    'Nevím': Colors.grey.shade300,
  };

  @override
  void initState() {
    super.initState();
    startTime = widget.currentPosition;
    endTime = (widget.currentPosition + 3.0).clamp(0.0, widget.duration);
  }

  String _formatDuration(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
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
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Spectrogram background
                  widget.spectogram!,

                  // The invisible slider on top for interaction
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
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.5,
              children: [
                _dialectOption('BC'),
                _dialectOption('BE'),
                _dialectOption('BiBh'),
                _dialectOption('BhBi'),
                _dialectOption('XB'),
                _dialectOption('Jiné'),
              ],
            ),
            SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    selectedDialect = 'Nevím';
                  });
                },
                child: Text(
                  'Nevím',
                  style: TextStyle(
                    color:
                    selectedDialect == 'Nevím' ? Colors.blue : Colors.black,
                    fontWeight: selectedDialect == 'Nevím'
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
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
    return InkWell(
      onTap: () {
        setState(() {
          selectedDialect = type;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          border: isSelected ? Border.all(color: Colors.blue, width: 2) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: dialectColors[type],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1),
              ),
            ),
            SizedBox(width: 8),
            Text(type),
            SizedBox(width: 4),
            Container(
              width: 24,
              height: 2,
              color: Colors.black,
            ),
          ],
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