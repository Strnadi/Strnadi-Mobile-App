/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
class FilteredRecordingPart {
  int? id; // local PK
  int? BEId; // backend filtered part id (unique if provided)
  int? recordingLocalId; // FK -> recordings.id
  int? recordingBEID; // parent backend recording id
  DateTime startDate;
  DateTime endDate;
  int state; // workflow state
  bool isRepresentant;
  int? parentBEID; // optional parent filtered part id (backend)
  int? parentLocalId; // optional parent filtered part id (local)

  FilteredRecordingPart({
    this.id,
    this.BEId,
    this.recordingLocalId,
    this.recordingBEID,
    required this.startDate,
    required this.endDate,
    required this.state,
    required this.isRepresentant,
    this.parentBEID,
    this.parentLocalId,
  });

  factory FilteredRecordingPart.fromDb(Map<String, Object?> row) {
    return FilteredRecordingPart(
      id: row['id'] as int?,
      BEId: row['BEId'] as int?,
      recordingLocalId: row['recordingLocalId'] as int?,
      recordingBEID: row['recordingBEID'] as int?,
      startDate: DateTime.parse(row['startDate'] as String),
      endDate: DateTime.parse(row['endDate'] as String),
      state: (row['state'] as num).toInt(),
      isRepresentant: ((row['representant'] as int?) ?? 0) == 1,
      parentBEID: row['parentBEID'] as int?,
      parentLocalId: row['parentLocalId'] as int?,
    );
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  factory FilteredRecordingPart.fromBEJson(Map<String, Object?> json) {
    final beidDyn = json['id'];
    final beid = (beidDyn is int)
        ? beidDyn
        : (beidDyn is String ? int.tryParse(beidDyn) : null);
    return FilteredRecordingPart(
      BEId: beid,
      recordingBEID: (json['recordingId'] as num?)?.toInt(),
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      state: (json['state'] as num).toInt(),
      isRepresentant: _parseBool(json['representantFlag']),
      parentBEID: (json['parentId'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toDbJson() {
    return {
      'id': id,
      'BEId': BEId,
      'recordingLocalId': recordingLocalId,
      'recordingBEID': recordingBEID,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'state': state,
      'representant': isRepresentant ? 1 : 0,
      'parentBEID': parentBEID,
      'parentLocalId': parentLocalId,
    };
  }
}