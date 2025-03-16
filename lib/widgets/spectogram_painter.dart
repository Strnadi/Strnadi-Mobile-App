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
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fftea/fftea.dart';
import 'package:wav/wav.dart';

final GlobalKey<_LiveSpectogramState> spectogramKey = GlobalKey<_LiveSpectogramState>();


class LiveSpectogram extends StatefulWidget {
  final List<double> data;
  final String? filepath;
  final Function(double pos)? getCurrentPosition;

  const LiveSpectogram.SpectogramLive({
    Key? key,
    this.getCurrentPosition,
    required this.data,
    this.filepath
  }) : super(key: key);

  @override
  _LiveSpectogramState createState() => _LiveSpectogramState();
}

class _LiveSpectogramState extends State<LiveSpectogram> {
  List<List<double>>? spectrogramData;
  final ScrollController _scrollController = ScrollController();
  double _zoom = 1.0;
  bool _isProcessing = false;

  // Current position in audio (for playback indicator)
  double currentPositionPx = 0;

  // Default width for each sample column
  final double _defaultColumnWidth = 2.0;

  @override
  void initState() {
    super.initState();
    _processAudio();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _processAudio() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    List<double> audio = [];
    if (widget.filepath != null) {
      final wav = await Wav.readFile(widget.filepath!);
      audio = _normalizeRmsVolume(wav.toMono(), 0.3);
    } else {
      audio = widget.data;
    }

    const chunkSize = 1024;
    final stft = STFT(chunkSize, Window.hanning(chunkSize));
    const buckets = 120;

    final List<List<double>> data = [];

    stft.run(
      audio,
          (Float64x2List chunk) {
        final amp = chunk.discardConjugates().magnitudes();
        final List<double> row = [];

        for (int bucket = 0; bucket < buckets; ++bucket) {
          int start = (amp.length * bucket) ~/ buckets;
          int end = (amp.length * (bucket + 1)) ~/ buckets;
          double power = _rms(Float64List.sublistView(amp, start, end));
          row.add(power);
        }
        data.add(row);
      },
      chunkSize ~/ 2,
    );

    if (mounted) {
      setState(() {
        spectrogramData = data;
        _isProcessing = false;
      });
    }
  }

  double _rms(List<double> audio) {
    if (audio.isEmpty) {
      return 0;
    }
    double squareSum = 0;
    for (final x in audio) {
      squareSum += x * x;
    }
    return math.sqrt(squareSum / audio.length);
  }

  Float64List _normalizeRmsVolume(List<double> audio, double target) {
    double factor = target / _rms(audio);
    final output = Float64List.fromList(audio);
    for (int i = 0; i < audio.length; ++i) {
      output[i] *= factor;
    }
    return output;
  }

  // Update current position (called from parent when playing audio)
  void updatePosition(Duration position, Duration total) {
    if (spectrogramData == null) return;

    // Calculate position as percentage of total
    final percentage = total.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / total.inMilliseconds;

    // Convert to pixels
    final totalWidth = spectrogramData!.length * _defaultColumnWidth * _zoom;
    final newPosition = percentage * totalWidth;

    if (currentPositionPx != newPosition) {
      setState(() {
        widget.getCurrentPosition?.call(newPosition);
        currentPositionPx = newPosition;
      });

      // Auto-scroll to follow playback position
      if (_scrollController.hasClients) {
        if (currentPositionPx > _scrollController.offset + MediaQuery.of(context).size.width - 100 ||
            currentPositionPx < _scrollController.offset + 100) {
          _scrollController.animateTo(
            math.max(0, currentPositionPx - MediaQuery.of(context).size.width / 2),
            duration: Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (spectrogramData == null) {
      return Center(child: CircularProgressIndicator());
    }

    // Calculate total width based on data and zoom
    final totalWidth = spectrogramData!.length * _defaultColumnWidth * _zoom;

    return Column(
      children: [
        // Zoom controls
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 16.0),
        //   child: Row(
        //     children: [
        //       Text('Zoom:'),
        //       Expanded(
        //         child: Slider(
        //           value: _zoom,
        //           min: 0.5,
        //           max: 5.0,
        //           onChanged: (value) {
        //             setState(() {
        //               _zoom = value;
        //             });
        //           },
        //         ),
        //       ),
        //       Text('${_zoom.toStringAsFixed(1)}x'),
        //     ],
        //   ),
        // ),

        // Scrollable spectrogram
        // Zoomable and pannable spectrogram
        Expanded(
          child: InteractiveViewer(
            maxScale: 5.0,
            minScale: 0.5,
            constrained: false,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(
                    spectrogramData!.length * _defaultColumnWidth,
                    MediaQuery.of(context).size.height * 0.3,
                  ),
                  painter: SpectrogramPainter(
                    spectrogramData!,
                    columnWidth: _defaultColumnWidth,
                  ),
                ),

                // Playback position indicator (static, won't follow zoom — needs mapping if desired)
                Positioned(
                  left: currentPositionPx,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.red,
                  ),
                ),

                // Time markers (may also be affected by zoom – should be synced if needed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 20,
                  child: CustomPaint(
                    size: Size(
                      spectrogramData!.length * _defaultColumnWidth,
                      20,
                    ),
                    painter: TimeMarkerPainter(
                      totalWidth: spectrogramData!.length * _defaultColumnWidth,
                      totalDuration: spectrogramData!.length * 0.02,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<List<double>> data;
  final double columnWidth;

  SpectrogramPainter(this.data, {this.columnWidth = 2.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final cellHeight = size.height / data[0].length;

    for (int x = 0; x < data.length; x++) {
      for (int y = 0; y < data[0].length; y++) {
        paint.color = _getColor(data[x][data[0].length - 1 - y]);
        canvas.drawRect(
          Rect.fromLTWH(
              x * columnWidth,
              y * cellHeight,
              columnWidth,
              cellHeight
          ),
          paint,
        );
      }
    }
  }

  Color _getColor(double power) {
    const scale = 2;
    final int red = (255 * math.min(1, power * scale)).toInt();
    final int green = (255 * math.min(1, power * scale / 2)).toInt();
    final int blue = (255 * math.min(1, power * scale / 4)).toInt();
    return Color.fromARGB(255, red, green, blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is SpectrogramPainter) {
      return oldDelegate.columnWidth != columnWidth;
    }
    return true;
  }
}

class TimeMarkerPainter extends CustomPainter {
  final double totalWidth;
  final double totalDuration; // in seconds

  TimeMarkerPainter({required this.totalWidth, required this.totalDuration});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw markers every second
    final double pixelsPerSecond = totalWidth / totalDuration;
    int markers = math.min(totalDuration.ceil(), 100); // Limit to avoid too many markers
    double interval = totalDuration / markers;

    for (int i = 0; i <= markers; i++) {
      final x = i * interval * pixelsPerSecond;
      final seconds = i * interval;

      // Draw marker line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, i % 5 == 0 ? 10 : 5), // Taller lines for major intervals
        paint,
      );

      // Draw time label for major intervals
      if (i % 5 == 0) {
        final minutes = (seconds / 60).floor();
        final remainingSeconds = (seconds % 60).floor();
        final text = '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';

        textPainter.text = TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: 10,
          ),
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 12),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}


