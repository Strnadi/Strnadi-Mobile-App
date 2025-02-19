import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpectrogramPainter extends CustomPainter {
  final List<List<double>> spectrogramData;
  final double maxIntensity;

  SpectrogramPainter(this.spectrogramData, this.maxIntensity);

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrogramData.isEmpty) return;

    final double columnWidth = size.width / spectrogramData.length;
    final double heightScale = size.height / spectrogramData[0].length;

    for (int timeIndex = 0; timeIndex < spectrogramData.length; timeIndex++) {
      final frequencies = spectrogramData[timeIndex];
      for (int freqIndex = 0; freqIndex < frequencies.length; freqIndex++) {
        final intensity = _normalizeDb(frequencies[freqIndex], maxIntensity);
        final color = _getColorFromIntensity(intensity);

        final rect = Rect.fromLTWH(
            timeIndex * columnWidth,
            size.height - (freqIndex + 1) * heightScale,
            columnWidth,
            heightScale
        );

        canvas.drawRect(rect, Paint()..color = color);
      }
    }
  }

  double _normalizeDb(double power, double maxPower) {
    const double minDb = -60.0;
    const double maxDb = 0.0;
    final db = 10 * math.log(power / maxPower) / math.ln10;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  }

  Color _getColorFromIntensity(double intensity) {
    intensity = intensity.clamp(0.0, 1.0);
    final hue = 120.0 * (1.0 - intensity);
    return HSVColor.fromAHSV(1.0, hue, 1.0, intensity).toColor();
  }

  @override
  bool shouldRepaint(SpectrogramPainter oldDelegate) => true;
}