import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';

import 'map_feature_filter_controls.dart';
import 'map_filter_defaults.dart';
import 'map_filter_selection.dart';

/// A draggable settings sheet that applies every selection immediately.
class MapFilterSheet extends StatefulWidget {
  const MapFilterSheet({
    super.key,
    required this.selection,
    required this.canFilterByUser,
    required this.onChanged,
  });

  final MapFilterSelection selection;
  final bool canFilterByUser;
  final ValueChanged<MapFilterSelection> onChanged;

  @override
  State<MapFilterSheet> createState() => _MapFilterSheetState();
}

class _MapFilterSheetState extends State<MapFilterSheet> {
  late MapFilterSelection _selection = widget.selection;

  @override
  void didUpdateWidget(MapFilterSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      _selection = widget.selection;
    }
  }

  void _change(MapFilterSelection selection) {
    setState(() => _selection = selection);
    widget.onChanged(selection);
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.55,
    minChildSize: 0.2,
    maxChildSize: 0.9,
    builder: (context, controller) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView(
          controller: controller,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Icon(
                Icons.unfold_more_rounded,
                color: Colors.grey.shade500,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                t('map.buttons.mapSettings'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FilterChoices<bool>(
              titleKey: 'map.filters.mapView.title',
              value: _selection.satelliteView,
              options: const {
                false: 'map.filters.mapView.classic',
                true: 'map.filters.mapView.satellite',
              },
              onChanged: (value) =>
                  _change(_selection.copyWith(satelliteView: value)),
            ),
            const SizedBox(height: 8),
            _FilterChoices<RecordingAgeFilter>(
              titleKey: 'map.filters.recordingAge.title',
              value: _selection.recordingAge,
              options: const {
                RecordingAgeFilter.older: 'map.filters.recordingAge.older',
                RecordingAgeFilter.newer: 'map.filters.recordingAge.newer',
                RecordingAgeFilter.all: 'map.filters.recordingAge.all',
              },
              onChanged: (value) =>
                  _change(_selection.copyWith(recordingAge: value)),
            ),
            const SizedBox(height: 8),
            MapOwnerFilterControl(
              value: _selection.authorFilter,
              canFilterByUser: widget.canFilterByUser,
              onChanged: (value) =>
                  _change(_selection.copyWith(authorFilter: value)),
            ),
            _FilterChoices<DialectVisibilityMode>(
              titleKey: 'map.filters.dialectVisibility.title',
              value: _selection.dialectVisibility,
              unselectedColor: Colors.grey,
              options: const {
                DialectVisibilityMode.all: 'map.filters.dialectVisibility.all',
                DialectVisibilityMode.aiAdmin:
                    'map.filters.dialectVisibility.aiAdmin',
                DialectVisibilityMode.adminOnly:
                    'map.filters.dialectVisibility.adminOnly',
              },
              onChanged: (value) =>
                  _change(_selection.copyWith(dialectVisibility: value)),
            ),
            const SizedBox(height: 8),
            _FilterChoices<bool>(
              titleKey: 'map.filters.clustering.title',
              value: _selection.clustered,
              options: const {
                true: 'map.filters.clustering.on',
                false: 'map.filters.clustering.off',
              },
              onChanged: (value) =>
                  _change(_selection.copyWith(clustered: value)),
            ),
            MapFeatureFilterControls(
              value: _selection.featureFilters,
              clustered: _selection.clustered,
              canFilterByUser: widget.canFilterByUser,
              onChanged: (value) =>
                  _change(_selection.copyWith(featureFilters: value)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('map-reset-filters'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _change(mapFilterDefaults),
                child: Text(t('map.buttons.resetFilters')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilterChoices<T> extends StatelessWidget {
  const _FilterChoices({
    required this.titleKey,
    required this.value,
    required this.options,
    required this.onChanged,
    this.unselectedColor,
  });

  final String titleKey;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Color? unselectedColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t(titleKey)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options.entries)
            OutlinedButton(
              key: ValueKey(option.value),
              onPressed: () => onChanged(option.key),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: value == option.key
                      ? Colors.black
                      : unselectedColor ?? Colors.grey.shade200,
                ),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(t(option.value)),
            ),
        ],
      ),
    ],
  );
}
