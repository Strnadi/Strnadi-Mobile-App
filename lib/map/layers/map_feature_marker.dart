import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:strnadi/api/models/map_clusters.dart';

/// Compact recording tiles and count badges for aggregated clusters.
class MapFeatureMarker extends StatelessWidget {
  const MapFeatureMarker({
    super.key,
    required this.feature,
    required this.onTap,
  });
  final MapCluster feature;
  final VoidCallback onTap;
  static double extent(MapCluster feature) => feature.isRecording ? 30 : 48;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${feature.count}: ${feature.dialects.map((d) => '${d.code} ${d.percentage}%').join(', ')}',
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: feature.isRecording
          ? Center(
              child: SizedBox.square(
                dimension: 20,
                child: CustomPaint(
                  painter: _RecordingTilePainter(feature.dialects),
                  child: feature.source == 'ai'
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            )
          : CustomPaint(
              painter: _PiePainter(feature.dialects),
              child: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '${feature.count}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.dialects);
  final List<MapClusterDialect> dialects;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (final dialect in dialects) {
      final sweep = 2 * math.pi * dialect.percentage / 100;
      canvas.drawArc(
        rect.deflate(2),
        start,
        sweep,
        true,
        Paint()..color = Color(dialect.color),
      );
      start += sweep;
    }
    canvas.drawOval(
      rect.deflate(2),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PiePainter oldDelegate) =>
      oldDelegate.dialects != dialects;
}

/// Diagonal color splits retain the server proportions, including more than
/// two dialects, without fetching colors or adding a badge to a single tile.
class _RecordingTilePainter extends CustomPainter {
  _RecordingTilePainter(this.dialects);
  final List<MapClusterDialect> dialects;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.5),
      const Radius.circular(6),
    );
    canvas.save();
    canvas.clipRRect(outline);
    var cumulative = 100.0;
    for (var i = dialects.length - 1; i >= 0; i--) {
      final fraction = (cumulative / 100).clamp(0.0, 1.0);
      final diagonal = fraction <= .5
          ? math.sqrt(2 * fraction)
          : 2 - math.sqrt(2 * (1 - fraction));
      final path = Path()..moveTo(0, 0);
      if (diagonal <= 1) {
        path
          ..lineTo(size.width * diagonal, 0)
          ..lineTo(0, size.height * diagonal);
      } else {
        path
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * (diagonal - 1))
          ..lineTo(size.width * (diagonal - 1), size.height)
          ..lineTo(0, size.height);
      }
      canvas.drawPath(path..close(), Paint()..color = Color(dialects[i].color));
      cumulative -= dialects[i].percentage;
    }
    canvas.restore();
    canvas.drawRRect(
      outline,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RecordingTilePainter oldDelegate) =>
      oldDelegate.dialects != dialects;
}
