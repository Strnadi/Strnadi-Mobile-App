import 'package:flutter/foundation.dart';
import 'package:strnadi/api/models/map_feature_filters.dart';

enum DialectVisibilityMode { all, aiAdmin, adminOnly }

enum RecordingAgeFilter { all, newer, older }

/// User-facing choices; conversion to the wire contract belongs to map state.
@immutable
class MapFilterSelection {
  const MapFilterSelection({
    required this.satelliteView,
    required this.authorFilter,
    required this.recordingAge,
    required this.dialectVisibility,
    required this.clustered,
    required this.featureFilters,
  });

  final bool satelliteView;
  final String authorFilter;
  final RecordingAgeFilter recordingAge;
  final DialectVisibilityMode dialectVisibility;
  final bool clustered;
  final MapFeatureFilters featureFilters;

  MapFilterSelection copyWith({
    bool? satelliteView,
    String? authorFilter,
    RecordingAgeFilter? recordingAge,
    DialectVisibilityMode? dialectVisibility,
    bool? clustered,
    MapFeatureFilters? featureFilters,
  }) => MapFilterSelection(
    satelliteView: satelliteView ?? this.satelliteView,
    authorFilter: authorFilter ?? this.authorFilter,
    recordingAge: recordingAge ?? this.recordingAge,
    dialectVisibility: dialectVisibility ?? this.dialectVisibility,
    clustered: clustered ?? this.clustered,
    featureFilters: featureFilters ?? this.featureFilters,
  );

  @override
  bool operator ==(Object other) =>
      other is MapFilterSelection &&
      other.satelliteView == satelliteView &&
      other.authorFilter == authorFilter &&
      other.recordingAge == recordingAge &&
      other.dialectVisibility == dialectVisibility &&
      other.clustered == clustered &&
      other.featureFilters == featureFilters;

  @override
  int get hashCode => Object.hash(
    satelliteView,
    authorFilter,
    recordingAge,
    dialectVisibility,
    clustered,
    featureFilters,
  );
}
