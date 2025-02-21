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
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fftea/fftea.dart';
import 'package:strnadi/auth/login.dart';
import 'package:wav/wav.dart';

class SpectrogramWidget extends StatefulWidget {
  final String filePath;

  const SpectrogramWidget({Key? key, required this.filePath}) : super(key: key);

  @override
  _SpectrogramWidgetState createState() => _SpectrogramWidgetState();
}

class _SpectrogramWidgetState extends State<SpectrogramWidget> {
  List<List<double>>? spectrogramData;

  @override
  void initState() {
    super.initState();
    _processAudio();
  }

  Future<void> _processAudio() async {
    final wav = await Wav.readFile(widget.filePath);
    final audio = _normalizeRmsVolume(wav.toMono(), 0.3);

    const chunkSize = 2048;
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

    setState(() {
      spectrogramData = data;
    });
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

  @override
  Widget build(BuildContext context) {
    return spectrogramData == null
        ? Center(child: CircularProgressIndicator())
        : CustomPaint(
      size: Size(double.infinity, double.infinity),
      painter: SpectrogramPainter(spectrogramData!),
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<List<double>> data;

  SpectrogramPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final cellWidth = size.width / data.length;
    final cellHeight = size.height / data[0].length;

    for (int y = 0; y < data[0].length; y++) {
      for (int x = 0; x < data.length; x++) {
        paint.color = _getColor(data[data.length - 1 - x][data[0].length - 1 - y]);
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }
  }

  Color _getColor(double power) {
    const scale = 1;
    final int red = (255 * math.min(1, power * scale)).toInt();
    final int green = (255 * math.min(1, power * scale / 2)).toInt();
    final int blue = (255 * math.min(1, power * scale / 4)).toInt();
    return Color.fromARGB(255, red, green, blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}