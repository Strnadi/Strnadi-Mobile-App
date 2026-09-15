import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/api/models/map_feature_filters.dart';

class MapOwnerFilterControl extends StatelessWidget {
  const MapOwnerFilterControl({
    super.key,
    required this.value,
    required this.canFilterByUser,
    required this.onChanged,
  });
  final String value;
  final bool canFilterByUser;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('map.filters.recordingAuthor.title')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in const {
              'all': 'map.filters.recordingAuthor.all',
              'me': 'map.filters.recordingAuthor.me',
              'others': 'map.filters.recordingAuthor.others',
            }.entries)
              OutlinedButton(
                key: ValueKey('map-owner-${option.key}'),
                onPressed: option.key == 'all' || canFilterByUser
                    ? () => onChanged(option.key)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: BorderSide(
                    color: value == option.key
                        ? Colors.black
                        : Colors.grey.shade200,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(t(option.value)),
              ),
          ],
        ),
        if (!canFilterByUser) Text(t('map.filters.features.signInRequired')),
      ],
    ),
  );
}

class MapFeatureFilterControls extends StatelessWidget {
  const MapFeatureFilterControls({
    super.key,
    required this.value,
    required this.clustered,
    required this.canFilterByUser,
    required this.onChanged,
  });
  final MapFeatureFilters value;
  final bool clustered;
  final bool canFilterByUser;
  final ValueChanged<MapFeatureFilters> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: ExpansionTile(
      key: const ValueKey('advanced-map-filters'),
      title: Text(t('map.filters.features.advanced')),
      tilePadding: EdgeInsets.zero,
      children: [
        SwitchListTile(
          key: const ValueKey('mixDialects'),
          contentPadding: EdgeInsets.zero,
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Color(0xFFE0E0E0),
          title: Text(t('map.filters.features.mixDialects')),
          subtitle: Text(t('map.filters.features.mixDialectsHelp')),
          value: value.mixDialects,
          onChanged: clustered
              ? (v) => onChanged(value.copyWith(mixDialects: v))
              : null,
        ),
        SwitchListTile(
          key: const ValueKey('mixSources'),
          contentPadding: EdgeInsets.zero,
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Color(0xFFE0E0E0),
          title: Text(t('map.filters.features.mixSources')),
          subtitle: Text(t('map.filters.features.mixSourcesHelp')),
          value: value.mixSources,
          onChanged: clustered
              ? (v) => onChanged(value.copyWith(mixSources: v))
              : null,
        ),
        if (!clustered) Text(t('map.filters.features.enableClustering')),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('onlyMeaningfulDialects'),
          contentPadding: EdgeInsets.zero,
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Color(0xFFE0E0E0),
          title: Text(t('map.filters.features.onlyMeaningfulDialects')),
          subtitle: Text(t('map.filters.features.onlyMeaningfulDialectsHelp')),
          value: value.onlyMeaningfulDialects,
          onChanged: (v) =>
              onChanged(value.copyWith(onlyMeaningfulDialects: v)),
        ),
        SwitchListTile(
          key: const ValueKey('hideOthersWithoutMeaningfulDialect'),
          contentPadding: EdgeInsets.zero,
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Color(0xFFE0E0E0),
          title: Text(
            t('map.filters.features.hideOthersWithoutMeaningfulDialect'),
          ),
          subtitle: Text(
            t(
              value.onlyMeaningfulDialects
                  ? 'map.filters.features.onlyMeaningfulOverrides'
                  : 'map.filters.features.hideOthersHelp',
            ),
          ),
          value: value.hideOthersWithoutMeaningfulDialect,
          onChanged: canFilterByUser
              ? (v) => onChanged(
                  value.copyWith(hideOthersWithoutMeaningfulDialect: v),
                )
              : null,
        ),
      ],
    ),
  );
}
