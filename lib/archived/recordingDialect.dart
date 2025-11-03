// class RecordingDialect{
//   int RecordingId;
//   String dialect;
//   DateTime StartDate;
//   DateTime EndDate;
//
//   RecordingDialect({
//     required this.RecordingId,
//     required this.dialect,
//     required this.StartDate,
//     required this.EndDate,
//   });
//
//   factory RecordingDialect.fromJson(Map<String, Object?> json) {
//     // Safely parse the ID, allowing for uppercase or lowercase keys
//     final dynamic idValue = json['recordingId'] ?? json['RecordingId'];
//     final int recordingId = idValue is int
//       ? idValue
//       : (idValue != null ? int.tryParse(idValue.toString()) ?? 0 : 0);
//
//     // Determine dialect: prefer first detectedDialects entry (string or map), else fallback to dialectCode
//     final List<dynamic> detectedList = (json['detectedDialects'] as List<dynamic>?) ?? [];
//     late final String dialectValue;
//     if (detectedList.isNotEmpty) {
//       final first = detectedList.first;
//       if (first is String) {
//         dialectValue = first;
//       } else if (first is Map<String, dynamic>) {
//         dialectValue = (first['dialect'] as String?)
//             ?? (first['dialectCode'] as String?)
//             ?? 'Nevyhodnoceno';
//       } else {
//         dialectValue = 'Nevyhodnoceno';
//       }
//     } else {
//       dialectValue = (json['dialectCode'] as String?) ?? 'Nevyhodnoceno';
//     }
//
//     // Helper to fetch raw date string from uppercase or lowercase key
//     String _getRawDate(String upperKey, String lowerKey) {
//       return json[upperKey] as String?
//           ?? json[lowerKey] as String?
//           ?? '';
//     }
//
//     // Robust date parser: empty → epoch; digits → epoch-from-ms; ISO parse otherwise
//     DateTime _parseDate(String raw) {
//       if (raw.isEmpty) {
//         return DateTime.fromMillisecondsSinceEpoch(0);
//       }
//       if (RegExp(r'^\d+$').hasMatch(raw)) {
//         return DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
//       }
//       try {
//         return DateTime.parse(raw);
//       } catch (_) {
//         return DateTime.fromMillisecondsSinceEpoch(0);
//       }
//     }
//
//     final DateTime startDate = _parseDate(_getRawDate('StartDate', 'startDate'));
//     final DateTime endDate   = _parseDate(_getRawDate('EndDate',   'endDate'));
//
//     return RecordingDialect(
//       RecordingId: recordingId,
//       dialect: dialectValue,
//       StartDate: startDate,
//       EndDate: endDate,
//     );
//   }
//
//
//   Map<String, Object?> toJson() {
//     return {
//       'recordingId': RecordingId,
//       'dialectCode': dialect,
//       'StartDate': StartDate.toString(),
//       'EndDate': EndDate.toString(),
//     };
//   }
//
//   List<RecordingDialect> fromJsonList(List<dynamic> jsonList) {
//     return jsonList.map((json) => RecordingDialect.fromJson(json)).toList();
//   }
// }
