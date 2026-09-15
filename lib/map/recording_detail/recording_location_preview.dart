import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/map/layers/map_tile_layers.dart';

class RecordingLocationPreview extends StatelessWidget {
  const RecordingLocationPreview({
    super.key,
    required this.position,
    required this.placeTitle,
  });

  final LatLng position;
  final String placeTitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    child: Column(
      children: [
        Row(children: [Expanded(child: Text(placeTitle))]),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 300,
            child: FlutterMap(
              key: ValueKey(position),
              options: MapOptions(
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
                initialCenter: position,
                initialZoom: 13,
              ),
              children: [
                const MapTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 20,
                      height: 20,
                      point: position,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
