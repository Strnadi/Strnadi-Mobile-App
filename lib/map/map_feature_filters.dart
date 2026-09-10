/// Options applied by the server before rendering map features.
class MapFeatureFilters {
  const MapFeatureFilters({
    this.mixDialects = true,
    this.mixSources = true,
    this.onlyMeaningfulDialects = false,
    this.hideOthersWithoutMeaningfulDialect = false,
  });

  static const defaults = MapFeatureFilters(
    hideOthersWithoutMeaningfulDialect: true,
  );

  /// Without an account, all recordings are other users' recordings.
  MapFeatureFilters forUser({required bool signedIn}) =>
      !signedIn && hideOthersWithoutMeaningfulDialect
      ? copyWith(
          onlyMeaningfulDialects: true,
          hideOthersWithoutMeaningfulDialect: false,
        )
      : this;

  final bool mixDialects;
  final bool mixSources;
  final bool onlyMeaningfulDialects;
  final bool hideOthersWithoutMeaningfulDialect;

  MapFeatureFilters copyWith({
    bool? mixDialects,
    bool? mixSources,
    bool? onlyMeaningfulDialects,
    bool? hideOthersWithoutMeaningfulDialect,
  }) => MapFeatureFilters(
    mixDialects: mixDialects ?? this.mixDialects,
    mixSources: mixSources ?? this.mixSources,
    onlyMeaningfulDialects:
        onlyMeaningfulDialects ?? this.onlyMeaningfulDialects,
    hideOthersWithoutMeaningfulDialect:
        hideOthersWithoutMeaningfulDialect ??
        this.hideOthersWithoutMeaningfulDialect,
  );

  Map<String, bool> toQueryParameters() => {
    'mixDialects': mixDialects,
    'mixSources': mixSources,
    'onlyMeaningfulDialects': onlyMeaningfulDialects,
    'hideOthersWithoutMeaningfulDialect': hideOthersWithoutMeaningfulDialect,
  };

  @override
  bool operator ==(Object other) =>
      other is MapFeatureFilters &&
      other.mixDialects == mixDialects &&
      other.mixSources == mixSources &&
      other.onlyMeaningfulDialects == onlyMeaningfulDialects &&
      other.hideOthersWithoutMeaningfulDialect ==
          hideOthersWithoutMeaningfulDialect;

  @override
  int get hashCode => Object.hash(
    mixDialects,
    mixSources,
    onlyMeaningfulDialects,
    hideOthersWithoutMeaningfulDialect,
  );
}
