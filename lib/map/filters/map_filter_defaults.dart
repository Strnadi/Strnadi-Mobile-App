import 'package:strnadi/api/models/map_feature_filters.dart';

import 'map_filter_selection.dart';

/// Shared by initial map state and Reset filters.
const mapFilterDefaults = MapFilterSelection(
  satelliteView: false,
  authorFilter: 'all',
  recordingAge: RecordingAgeFilter.newer,
  dialectVisibility: DialectVisibilityMode.aiAdmin,
  clustered: false,
  featureFilters: MapFeatureFilters(
    mixDialects: true,
    mixSources: true,
    onlyMeaningfulDialects: false,
    hideOthersWithoutMeaningfulDialect: true,
  ),
);
