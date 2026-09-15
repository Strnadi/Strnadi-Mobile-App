import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const initialMapPosition = LatLng(50.0755, 14.4378);
const initialMapZoom = 13.0;

/// Camera animation has its own lifecycle and never loads data itself.
class MapCameraController {
  MapCameraController(this.mapController);
  final MapController mapController;
  Timer? _animation;
  bool get isAnimating => _animation?.isActive == true;

  void cancelAnimation() => _animation?.cancel();

  void animateTo({
    required LatLng center,
    required double zoom,
    required void Function() onSettled,
  }) {
    cancelAnimation();
    final start = mapController.camera.center;
    final startZoom = mapController.camera.zoom;
    final longitudeDelta =
        ((center.longitude - start.longitude + 540) % 360) - 180;
    final watch = Stopwatch()..start();
    _animation = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final progress = (watch.elapsedMilliseconds / 300).clamp(0.0, 1.0);
      final eased = Curves.easeInOut.transform(progress);
      mapController.move(
        LatLng(
          start.latitude + (center.latitude - start.latitude) * eased,
          ((start.longitude + longitudeDelta * eased + 540) % 360) - 180,
        ),
        startZoom + (zoom - startZoom) * eased,
      );
      if (progress >= 1) {
        timer.cancel();
        onSettled();
      }
    });
  }

  void dispose() => cancelAnimation();
}
