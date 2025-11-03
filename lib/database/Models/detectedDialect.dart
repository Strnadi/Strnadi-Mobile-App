class DetectedDialect {
  int? id; // local PK
  int? BEId; // backend dialect id
  int? filteredPartLocalId; // FK -> FilteredRecordingParts.id
  int? filteredPartBEID; // parent FRP backend id
  int? userGuessDialectId;
  String? userGuessDialect;
  int? confirmedDialectId;
  String? confirmedDialect;

  DetectedDialect({
    this.id,
    this.BEId,
    this.filteredPartLocalId,
    this.filteredPartBEID,
    this.userGuessDialectId,
    this.userGuessDialect,
    this.confirmedDialectId,
    this.confirmedDialect,
  });

  factory DetectedDialect.fromDb(Map<String, Object?> row) {
    return DetectedDialect(
      id: row['id'] as int?,
      BEId: row['BEId'] as int?,
      filteredPartLocalId: row['filteredPartLocalId'] as int?,
      filteredPartBEID: row['filteredPartBEID'] as int?,
      userGuessDialectId: row['userGuessDialectId'] as int?,
      userGuessDialect: row['userGuessDialect'] as String?,
      confirmedDialectId: row['confirmedDialectId'] as int?,
      confirmedDialect: row['confirmedDialect'] as String?,
    );
  }

  factory DetectedDialect.fromBEJson(
      Map<String, Object?> json, {
        required int parentFilteredPartBEID,
      }) {
    final beidDyn = json['id'];
    final beid = (beidDyn is int)
        ? beidDyn
        : (beidDyn is String ? int.tryParse(beidDyn) : null);
    return DetectedDialect(
      BEId: beid,
      filteredPartBEID: parentFilteredPartBEID,
      userGuessDialectId: (json['userGuessDialectId'] as num?)?.toInt(),
      userGuessDialect: json['userGuessDialect'] as String?,
      confirmedDialectId: (json['confirmedDialectId'] as num?)?.toInt(),
      confirmedDialect: json['confirmedDialect'] as String?,
    );
  }

  Map<String, Object?> toDbJson() {
    return {
      'id': id,
      'BEId': BEId,
      'filteredPartLocalId': filteredPartLocalId,
      'filteredPartBEID': filteredPartBEID,
      'userGuessDialectId': userGuessDialectId,
      'userGuessDialect': userGuessDialect,
      'confirmedDialectId': confirmedDialectId,
      'confirmedDialect': confirmedDialect,
    };
  }
}