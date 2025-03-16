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

                  // Left handle/marker
                  Positioned(
                    left: (startTime / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                    child: _buildMarker(Colors.blue),
                  ),

                  // Right handle/marker
                  Positioned(
                    left: (endTime / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                    child: _buildMarker(Colors.blue),
                  ),

                  // Vertical line for left marker
                  Positioned(
                    left: (startTime / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                    child: Container(
                      width: 2,
                      height: 200,
                      color: Colors.blue,
                    ),
                  ),

                  // Vertical line for right marker
                  Positioned(
                    left: (endTime / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                    child: Container(
                      width: 2,
                      height: 200,
                      color: Colors.blue,
                    ),
                  ),

                  // Center selection bar
                  Positioned(
                    left: (startTime / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                    child: Container(
                      width: ((endTime - startTime) / widget.duration) * MediaQuery.of(context).size.width * 0.8,
                      height: 200,
                      decoration: BoxDecoration(
                        color: selectedDialect != null
                            ? dialectColors[selectedDialect]!.withOpacity(0.3)
                            : Colors.red.withOpacity(0.2),
                      ),
                    ),
                  ),

                  // The invisible slider on top for interaction
                  Positioned.fill(
                    child: SliderTheme(
                      data: SliderThemeData(
                        thumbShape: SliderComponentShape.noThumb,
                        overlayShape: SliderComponentShape.noOverlay,
                        trackShape: CustomTrackShape(),
                        trackHeight: 200,
                      ),
                      child: RangeSlider(
                        values: RangeValues(startTime, endTime),
                        min: 0.0,
                        max: widget.duration,
                        divisions: widget.duration.toInt() * 10, // 0.1 second precision
                        onChanged: (RangeValues values) {
                          setState(() {
                            startTime = values.start;
                            endTime = values.end;
                          });
                        },
                        activeColor: Colors.transparent,
                        inactiveColor: Colors.transparent,
                      ),
                    ),
                  ),
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