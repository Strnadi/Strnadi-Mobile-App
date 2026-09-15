import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:strnadi/api/controllers/maps_controller.dart';
import 'package:strnadi/api/map_tile_provider.dart';

class MapTileLayer extends StatefulWidget {
  const MapTileLayer({this.style = MapTileStyle.outdoor, this.host, super.key});

  final MapTileStyle style;
  final String? host;

  @override
  State<MapTileLayer> createState() => _MapTileLayerState();
}

class _MapTileLayerState extends State<MapTileLayer> {
  late final NetworkTileProvider _provider = createMapTileProvider();

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: const MapsController().tileUrlTemplate(
      style: widget.style,
      host: widget.host,
    ),
    tileProvider: _provider,
    userAgentPackageName: 'cz.delta.strnadi',
  );
}
