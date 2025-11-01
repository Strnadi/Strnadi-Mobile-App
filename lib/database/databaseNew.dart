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

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/PostRecordingForm/addDialect.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/user/settingsManager.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:strnadi/recording/waw.dart';
import 'package:strnadi/dialects/ModelHandler.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../notificationPage/notifications.dart';
import 'fileSize.dart';

final logger = Logger();

Future<String> getPath() async {
  final dir = await getApplicationDocumentsDirectory();
  String path = dir.path + 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
  logger.i('Generated file path: $path');
  return path;
}

class UserData {
  String FirstName;
  String LastName;
  String? NickName;

  String? ProfilePic;

  String? format;

  UserData(
      {required this.FirstName,
      required this.LastName,
      this.NickName,
      this.ProfilePic,
      this.format});

  factory UserData.fromJson(Map<String, Object?> json) {
    return UserData(
        FirstName: json['firstName'] as String,
        LastName: json['lastName'] as String,
        NickName: json['nickname'] as String?);
  }
}

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

class RecordingUnready {
  int? id;
  String? mail;
  DateTime? createdAt;
  int? estimatedBirdsCount;
  String? device;
  bool? byApp;
  String? note;
  String? path;

  RecordingUnready({
    this.id,
    this.mail,
    this.createdAt,
    this.estimatedBirdsCount,
    this.device,
    this.byApp,
    this.note,
    this.path,
  });
}

class RecordingPartUnready {
  int? id;
  int? recordingId;
  DateTime? startTime;
  DateTime? endTime;
  double? gpsLatitudeStart;
  double? gpsLatitudeEnd;
  double? gpsLongitudeStart;
  double? gpsLongitudeEnd;
  //String? dataBase64;
  String? path;

  RecordingPartUnready(
      {this.id,
      this.recordingId,
      this.startTime,
      this.endTime,
      this.gpsLatitudeStart,
      this.gpsLatitudeEnd,
      this.gpsLongitudeStart,
      this.gpsLongitudeEnd,
      this.path
      //this.dataBase64,
      });
}

class Recording {
  int? id;
  int? userId;
  int? BEId;
  String? mail;
  DateTime createdAt;
  int estimatedBirdsCount;
  String? device;
  bool byApp;
  String? note;
  String? name;
  String? path;
  bool downloaded;
  bool sent;
  bool sending;
  double? totalSeconds;
  int? partCount;
  String env;

  Recording({
    this.id,
    this.userId,
    this.BEId,
    this.mail,
    required this.createdAt,
    required this.estimatedBirdsCount,
    this.device,
    required this.byApp,
    this.note,
    this.name,
    this.path,
    this.downloaded = true,
    this.sent = false,
    this.sending = false,
    required this.partCount,
    required this.env,
    this.totalSeconds,
  });

  factory Recording.fromJson(Map<String, Object?> json) {
    return Recording(
      id: json['id'] as int?,
      userId: json['userId'] as int?,
      BEId: json['BEId'] as int?,
      mail: json['mail'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      estimatedBirdsCount: json['estimatedBirdsCount'] as int,
      device: json['device'] as String?,
      byApp: (json['byApp'] as int) == 1,
      note: json['note'] as String?,
      name: json['name'] as String?,
      path: json['path'] as String?,
      totalSeconds: json['totalSeconds'] as double?,
      sent: (json['sent'] as int) == 1,
      downloaded: (json['downloaded'] as int) == 1,
      sending: (json['sending'] as int) == 1,
      partCount: json['partCount'] as int? ?? 0,
      env: json['env'] as String? ?? 'prod',
    );
  }

  factory Recording.fromUnready(RecordingUnready unready, int partCount) {
    if (unready.id == null ||
        unready.mail == null ||
        unready.createdAt == null ||
        unready.estimatedBirdsCount == null ||
        unready.device == null ||
        unready.byApp == null ||
        unready.path == null) {
      throw UnreadyException('Recording is not ready');
    }
    return Recording(
        id: unready.id,
        BEId: null,
        mail: unready.mail ?? '',
        createdAt: unready.createdAt!,
        estimatedBirdsCount: unready.estimatedBirdsCount ?? 0,
        device: unready.device,
        byApp: unready.byApp ?? true,
        note: unready.note,
        path: unready.path,
        sent: false,
        downloaded: true,
        sending: false,
        totalSeconds: -1.0,
        partCount: partCount,
        env: Config.hostEnvironment.name.toString());
  }

  factory Recording.fromBEJson(Map<String, Object?> json, int? userId) {
    return Recording(
      BEId: json['id'] as int?,
      userId: userId ?? json['userId'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      estimatedBirdsCount: json['estimatedBirdsCount'] as int,
      device: json['device'] as String?,
      byApp: json['byApp'] as bool,
      note: json['note'] as String?,
      name: json['name'] as String?,
      sent: true,
      downloaded: false,
      path: null,
      sending: false,
      partCount: int.tryParse(json['expectedPartsCount'].toString()),
      env: Config.hostEnvironment.name.toString(),
      totalSeconds: double.parse(json['totalSeconds'].toString()),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'BEId': BEId,
      'mail': mail,
      'createdAt': createdAt.toString(),
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp ? 1 : 0,
      'note': note,
      'name': name,
      'path': path,
      'sent': sent ? 1 : 0,
      'downloaded': downloaded ? 1 : 0,
      'sending': sending ? 1 : 0,
      'partCount': partCount,
      'totalSeconds': totalSeconds,
      'env': env,
    };
  }

  Future<Map<String, Object?>> toBEJson() async {
    final String? deviceId = await FlutterSecureStorage().read(key: 'fcmToken');
    logger.i('Fetched deviceId for BE JSON: $deviceId');
    final Map<String, Object?> body = {
      'id': BEId,
      'createdAt': createdAt.toIso8601String(),
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp,
      'note': note,
      'name': name,
      'expectedPartsCount': partCount,
      'deviceId': deviceId,
    };
    logger.i('Generated BE JSON for Recording: $body');
    return body;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Recording) return false;
    bool equal = true;
    if (mail != null && other.mail != null) {
      equal = equal && mail == other.mail;
    }
    if (createdAt != null && other.createdAt != null) {
      equal = equal && createdAt == other.createdAt;
    }
    if (estimatedBirdsCount != null && other.estimatedBirdsCount != null) {
      equal = equal && estimatedBirdsCount == other.estimatedBirdsCount;
    }
    if (device != null && other.device != null) {
      equal = equal && device == other.device;
    }
    if (byApp != null && other.byApp != null) {
      equal = equal && byApp == other.byApp;
    }
    if (note != null && other.note != null) {
      equal = equal && note == other.note;
    }
    return equal;
  }

  @override
  int get hashCode {
    return Object.hash(
      BEId ?? 0,
      mail,
      createdAt,
      estimatedBirdsCount,
      device ?? '',
      byApp,
      note ?? '',
    );
  }
}

class RecordingPart {
  int? id;
  int? BEId;
  int? recordingId;
  int? backendRecordingId;
  DateTime startTime;
  DateTime endTime;
  double gpsLatitudeStart;
  double gpsLatitudeEnd;
  double gpsLongitudeStart;
  double gpsLongitudeEnd;
  String? square;
  String? dataBase64Temp;
  String? path;
  int? length;
  bool sent;
  bool sending;

  RecordingPart({
    this.id,
    this.BEId,
    required this.recordingId,
    required this.startTime,
    required this.endTime,
    required this.gpsLatitudeStart,
    required this.gpsLatitudeEnd,
    required this.gpsLongitudeStart,
    required this.gpsLongitudeEnd,
    this.square,
    this.path,
    this.length,
    this.dataBase64Temp,
    this.sent = false,
    this.sending = false,
  });

  factory RecordingPart.fromJson(Map<String, Object?> json) {
    return RecordingPart(
        id: json['id'] as int?,
        BEId: json['BEId'] as int?,
        recordingId: json['recordingId'] as int?,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
        gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
        gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
        gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
        square: json['square'] as String?,
        sent: (json['sent'] as int) == 1,
        sending: (json['sending'] as int) == 1,
        path: json['path'] as String?,
        length: json['length'] as int?);
  }

  factory RecordingPart.fromBEJson(
      Map<String, Object?> json, int backendRecordingId) {
    return RecordingPart(
        BEId: json['id'] as int?,
        recordingId: null, // will be updated later
        startTime: DateTime.parse(json['startDate'] as String),
        endTime: DateTime.parse(json['endDate'] as String),
        gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
        gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
        gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
        gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
        dataBase64Temp: json['dataBase64'] as String?,
        square: json['square'] as String?,
        sent: true,
        length: json['length'] as int?)
      ..backendRecordingId = backendRecordingId;
  }

  Future<void> save() async {
    String newPath = (await getApplicationDocumentsDirectory()).path +
        "/recording_${DateTime.now().millisecondsSinceEpoch}.wav";
    File file = await File(newPath).create();
    await file.writeAsBytes(base64Decode(dataBase64Temp!));
    this.path = newPath;
  }

  factory RecordingPart.fromUnready(RecordingPartUnready unready) {
    if (unready.startTime == null ||
        unready.endTime == null ||
        unready.gpsLatitudeStart == null ||
        unready.gpsLatitudeEnd == null ||
        unready.gpsLongitudeStart == null ||
        unready.gpsLongitudeEnd == null ||
        unready.path == null) {
      logger.i(
          'Recording part is not ready. Part id: ${unready.id}, recording id: ${unready.recordingId}, start time: ${unready.startTime}, end time: ${unready.endTime}, gpsLatitudeStart: ${unready.gpsLatitudeStart}, gpsLatitudeEnd: ${unready.gpsLatitudeEnd}, gpsLongitudeStart: ${unready.gpsLongitudeStart}, gpsLongitudeEnd: ${unready.gpsLongitudeEnd}, path: ${unready.path}');
      throw UnreadyException('Recording part is not ready');
    }
    return RecordingPart(
      id: unready.id,
      BEId: null,
      recordingId: unready.recordingId,
      startTime: unready.startTime!,
      endTime: unready.endTime!,
      gpsLatitudeStart: unready.gpsLatitudeStart ?? 0.0,
      gpsLatitudeEnd: unready.gpsLatitudeEnd ?? 0.0,
      gpsLongitudeStart: unready.gpsLongitudeStart ?? 0.0,
      gpsLongitudeEnd: unready.gpsLongitudeEnd ?? 0.0,
      path: unready.path,
      //dataBase64Temp: unready.dataBase64,
      square: null,
      sent: false,
    );
  }

  Map<String, Object?> toBEJson() {
    return {
      'id': BEId,
      'recordingId': backendRecordingId,
      'startDate': startTime.toIso8601String(),
      'endDate': endTime.toIso8601String(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'dataBase64': dataBase64,
    };
  }

  Map<String, Object?> toBEJsonWithoutData() {
    return {
      'id': BEId,
      'recordingId': backendRecordingId,
      'startDate': startTime.toIso8601String(),
      'endDate': endTime.toIso8601String(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'BEId': BEId,
      'backendRecordingId': backendRecordingId, // new field
      'recordingId': recordingId,
      'startTime': startTime.toString(),
      'endTime': endTime.toString(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'path': path,
      'square': square,
      'sent': sent ? 1 : 0,
      'sending': sending ? 1 : 0,
      'length': length
    };
  }

  String? get dataBase64 {
    if (this.path == null) return null;
    File file = File(this.path!);
    String base64String = base64Encode(file.readAsBytesSync());
    return base64String;
  }
}

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

typedef UploadProgress = void Function(int sent, int total);

/// Database helper class
class DatabaseNew {
  static Database? _database;
  static List<Recording> recordings = List<Recording>.empty(growable: true);
  static List<RecordingPart> recordingParts =
      List<RecordingPart>.empty(growable: true);
  static List<FilteredRecordingPart> filteredRecordingParts =
      List<FilteredRecordingPart>.empty(growable: true);
  static List<DetectedDialect> detectedDialects =
      List<DetectedDialect>.empty(growable: true);

  static List<FilteredRecordingPart>? fetchedFilteredRecordingParts;
  static List<DetectedDialect>? fetchedDetectedDialects;

  static List<Recording>? fetchedRecordings;
  static List<RecordingPart>? fetchedRecordingParts;

  static bool fetching = false;
  static bool loadedRecordings = false;

  /// Enforces the user-defined maximum number of local recordings by deleting the oldest ones.
  static Future<void> enforceMaxRecordings() async {
    logger.i('Enforcing maximum number of local recordings.');
    final int max = await SettingsService().getLocalRecordingsMax();
    logger.i('Maximum allowed recordings: $max');
    if (max <= 0) return; // no limit or invalid

    // Need user scoping (mail + env) to avoid touching other users/environments
    final Database db = await database;
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null || jwt.isEmpty) return;
    final String email = JwtDecoder.decode(jwt)['sub'];
    final String env = Config.hostEnvironment.name.toString();

    // Count only eligible rows (all parts sent, none sending, downloaded)
    final List<Map<String, Object?>> cntRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ('
      '  SELECT r.id '
      '  FROM recordings r '
      '  LEFT JOIN recordingParts p ON p.recordingId = r.id '
      '  WHERE r.mail = ? AND r.env = ? AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      '  GROUP BY r.id '
      '  HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0'
      ') t',
      [email, env],
    );

    int totalEligible;
    final dynamic cVal = cntRows.first['c'];
    if (cVal is int) {
      totalEligible = cVal;
    } else if (cVal is num) {
      totalEligible = cVal.toInt();
    } else if (cVal is String) {
      totalEligible = int.tryParse(cVal) ?? 0;
    } else {
      totalEligible = 0;
    }

    if (totalEligible <= max) return; // under limit
    final int toDelete = totalEligible - max;

    // Fetch the oldest eligible recording ids (and paths) using SQLite ordering/limit with all parts sent, none sending, downloaded
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT r.id, r.path '
      'FROM recordings r '
      'LEFT JOIN recordingParts p ON p.recordingId = r.id '
      'WHERE r.mail = ? AND r.env = ? AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      'GROUP BY r.id '
      'HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0 '
      'ORDER BY datetime(r.createdAt) ASC LIMIT ?',
      [email, env, toDelete],
    );

    // Delete the chosen ids using our existing helper (ensures parts + files are cleaned up)
    for (final Map<String, Object?> row in rows) {
      final dynamic idVal = row['id'];
      final int id = idVal is int
          ? idVal
          : (idVal is num ? idVal.toInt() : int.parse(idVal.toString()));
      try {
        await deleteRecordingFromCache(id);
        logger.i('Auto-pruned recording id $id due to max limit=$max');
      } catch (e, st) {
        logger.e('Failed to auto-prune recording id $id',
            error: e, stackTrace: st);
        Sentry.captureException(e, stackTrace: st);
      }
    }
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<int> insertRecording(Recording recording) async {
    try {
      final db = await database;
      if (recording.BEId != null) {
        List<Map<String, dynamic>> existing = await db.query("recordings",
            where: "BEId = ?", whereArgs: [recording.BEId]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recording.id = id;
          await updateRecording(recording);
          int index = recordings.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordings[index] = recording;
          } else {
            recordings.add(recording);
          }
          logger.i(
              'Recording with BEId ${recording.BEId} updated (id: $id), path: ${recording.path}');
          return id;
        }
      }
      String? token = await FlutterSecureStorage().read(key: 'token');

      logger.i("token: $token");

      if (token == null || token == '') {
        recording.mail = '';
      } else {
        recording.mail = JwtDecoder.decode(token)['sub'];
      }
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      recordings.add(recording);
      if (token != null && token != '') {
        await enforceMaxRecordings();
      }
      logger.i('Recording ${recording.id} inserted, path: ${recording.path}');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  // static method to select all
  static Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> recs =
        await db.rawQuery("SELECT * FROM recordings");
    return recs;
  }

  // update all recordings where there is no email to have the mail from the jwt
  static Future<void> updateRecordingsMail() async {
    final db = await database;
    final String? token = await FlutterSecureStorage().read(key: 'token');
    if (token == null || token == '') return;
    final String email = JwtDecoder.decode(token)['sub'];
    await db
        .rawUpdate('UPDATE recordings SET mail = ? WHERE mail IS ""', [email]);
  }

  static Future<int> insertRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      if (recordingPart.id != null) {
        List<Map<String, dynamic>> existing = await db.query("recordingParts",
            where: "id = ?", whereArgs: [recordingPart.id]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recordingPart.id = id;
          await updateRecordingPart(recordingPart);
          int index = recordingParts.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordingParts[index] = recordingPart;
          } else {
            recordingParts.add(recordingPart);
          }
          logger.i(
              'Recording part with backendRecordingId ${recordingPart.backendRecordingId} updated (id: $id).');
          return id;
        }
      }
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      recordingParts.add(recordingPart);
      logger.i('Recording part ${recordingPart.id} inserted.');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<void> onFetchFinished() async {
    List<Recording> oldRecordings = await getRecordings();
    List<Recording> sentRecordings =
        oldRecordings.where((recording) => recording.sent).toList();

    if (fetchedRecordings == null || fetchedRecordingParts == null) {
      logger.i('No recordings fetched from backend.');
      return;
    }
    if (fetchedRecordings!.isEmpty || fetchedRecordingParts!.isEmpty) {
      logger.i('No recordings fetched from backend.');
      return;
    }

    // Delete sent recordings missing on backend
    for (Recording recording in sentRecordings) {
      if (!fetchedRecordings!.any((f) => f.BEId == recording.BEId)) {
        await deleteRecordingFromCache(recording.id!);
        logger.i(
            'Recording id ${recording.id} deleted locally (missing on backend).');
      }
    }

    List<Recording> newRecordings = fetchedRecordings!
        .where(
            (recording) => !sentRecordings.any((r) => r.BEId == recording.BEId))
        .toList();

    for (Recording recording in newRecordings) {
      recording.sent = true;
      recording.downloaded = false;
      logger.i(
          'Inserting recording with BEId: ${recording.BEId} and name ${recording.name}');
      await insertRecording(recording);
    }

    List<RecordingPart> oldRecordingParts = await getRecordingParts();
    List<RecordingPart> newRecordingParts = fetchedRecordingParts!
        .where(
            (newPart) => !oldRecordingParts.any((p) => p.BEId == newPart.BEId))
        .toList();

    for (RecordingPart recordingPart in newRecordingParts) {
      recordingPart.sent = true;
      Recording? localRecording;
      try {
        localRecording = recordings
            .firstWhere((r) => r.BEId == recordingPart.backendRecordingId);
      } catch (e) {
        localRecording = null;
      }
      if (localRecording != null) {
        recordingPart.recordingId = localRecording.id;
      }
      await insertRecordingPart(recordingPart);
    }
  }

  static Future<void> syncRecordings() async {
    if (fetching) return;
    logger.i("🔄 Syncing recordings...");
    try {
      await fetchRecordingsFromBE();
      final List<Recording> localRecordings = await getRecordings();
      final Set<int?> beIds =
          fetchedRecordings?.map((r) => r.BEId).toSet() ?? {};
      for (var local in localRecordings) {
        if (local.sent && !beIds.contains(local.BEId)) {
          await deleteRecordingFromCache(local.id!);
          logger.i(
              'Recording id ${local.id} deleted locally (missing on backend, during sync).');
        }
      }
      await onFetchFinished();
      if (fetchedRecordings != null && fetchedRecordings!.isNotEmpty) {
        await fetchFilteredPartsForRecordingsFromBE(fetchedRecordings!);
        await persistFetchedFilteredParts();
      }
      logger.i("✅ Recordings fetched and synced.");
    } catch (e, stackTrace) {
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<List<Recording>> getRecordings() async {
    final db = await database;
    final String jwt = await FlutterSecureStorage().read(key: 'token') ?? '';
    final String email = JwtDecoder.decode(jwt)['sub'];
    final List<Map<String, dynamic>> recs = await db.query("recordings",
        where: "mail = ? AND env = ?",
        whereArgs: [email, Config.hostEnvironment.name.toString()]);
    return List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
  }

  static Future<List<RecordingPart>> getRecordingParts() async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query("recordingParts");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<void> deleteRecording(int id) async {
    try {
      // Try to obtain the in‑memory instance of the recording
      Recording? recording;
      try {
        recording = await getRecordingFromDbById(id);
      } catch (_) {
        recording = null;
      }

      /* ------------------------------------------------------------------
       * 1) Delete on backend (only if already sent and BEId is known)
       * ------------------------------------------------------------------ */
      if (recording != null && recording.sent && recording.BEId != null) {
        final String? jwt = await FlutterSecureStorage().read(key: 'token');
        if (jwt != null) {
          final Uri url = Uri(
            scheme: 'https',
            host: Config.host,
            path: '/recordings/${recording.BEId}',
          );
          final http.Response resp = await http.delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200 || resp.statusCode == 204) {
            logger.i('Recording BEId ${recording.BEId} deleted on backend.');
          } else {
            logger.w(
              'Backend deletion failed for BEId ${recording.BEId}. '
              'Status: ${resp.statusCode} – Body: ${resp.body}',
            );
          }
        } else {
          logger.w(
              'JWT not available – skipping backend delete for BEId ${recording?.BEId}');
        }
      }

      /* ------------------------------------------------------------------
       * 2) Delete locally (DB rows, cached files, in‑memory lists)
       * ------------------------------------------------------------------ */
      final Database db = await database;

      // Remove audio part files + rows
      for (final RecordingPart part
          in List<RecordingPart>.from(recordingParts)) {
        if (part.recordingId == id) {
          if (part.path != null) {
            try {
              await File(part.path!).delete();
            } catch (_) {
              /* ignore file‑system errors */
            }
          }
          recordingParts.remove(part);
        }
      }
      await db
          .delete('recordingParts', where: 'recordingId = ?', whereArgs: [id]);

      // Remove main audio file if any
      if (recording?.path != null) {
        try {
          await File(recording!.path!).delete();
        } catch (_) {
          /* ignore file‑system errors */
        }
      }

      // Remove recording row + in‑memory instance
      recordings.removeWhere((r) => r.id == id);
      await db.delete('recordings', where: 'id = ?', whereArgs: [id]);

      logger.i(
          'Recording id $id deleted locally (and on backend if applicable).');
    } catch (e, stackTrace) {
      logger.e('Failed to delete recording id $id',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> sendRecordingBackground(int recordingId) async {
    await Workmanager().registerOneOffTask(
      (Platform.isIOS)
          ? "com.delta.strnadi.sendRecording"
          : "sendRecording_${DateTime.now().microsecondsSinceEpoch}",
      (Platform.isIOS)
          ? "sendRecording_${DateTime.now().microsecondsSinceEpoch}"
          : "sendRecording",
      inputData: {"recordingId": recordingId},
    );
  }

  static Future<void> sendRecording(
      Recording recording, List<RecordingPart> recordingParts) async {
    if (!await hasInternetAccess()) {
      logger.i('No internet connection. Recording will not be sent.');
      recording.sending = false;
      await updateRecording(recording);
      return;
    }
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      recording.sending = false;
      await updateRecording(recording);
      throw FetchException('Failed to send recording to backend', 401);
    }
    final http.Response response = await http.post(
      Uri.https(Config.host, '/recordings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(await recording.toBEJson()),
    );
    if (response.statusCode == 200) {
      logger.i(
          'Recording sent successfully. Sending parts. Response: ${response.body}');
      recording.BEId = jsonDecode(response.body);
      await updateRecording(recording);

      for (RecordingPart part in recordingParts) {
        part.recordingId = recording.id;
        part.backendRecordingId = recording.BEId;
        await sendRecordingPart(part);
      }
      recording.sent = true;
      recording.sending = false;
      await updateRecording(recording);
      logger.i('Recording id ${recording.id} sent successfully.');
    } else {
      recording.sending = false;
      await updateRecording(recording);
      throw UploadException(
          'Failed to send recording to backend', response.statusCode);
    }
  }

  static Future<void> sendRecordingNew(
      Recording recording, List<RecordingPart> recordingParts) async {
    if (!await Config.canUpload) {
      logger.i('Uploads are disabled by configuration.');
      recording.sending = false;
      await updateRecording(recording);
      throw Exception('Uploads are disabled by configuration.');
    }
    logger.i('Sending recording id: ${recording.id}');
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      recording.sending = false;
      await updateRecording(recording);
      throw FetchException('Failed to send recording to backend', 401);
    }
    try {
      final Map<String, Object?> body = await recording.toBEJson();
      logger.i('Sending recording with body: $body');
      final http.Response response = await http.post(
        Uri.https(Config.host, '/recordings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        logger.i(
            'Recording sent successfully. Sending parts. Response: ${response.body}');
        recording.BEId = jsonDecode(response.body);
        await updateRecording(recording);

        for (RecordingPart part in recordingParts) {
          try {
            part.recordingId = recording.id;
            part.backendRecordingId = recording.BEId;
            await sendRecordingPartNew(part);
          } catch (e, stackTrace) {
            if (e is PathNotFoundException) {
              logger.e('Path not found for recording part id: ${part.id}',
                  error: e, stackTrace: stackTrace);
              Sentry.captureException(e, stackTrace: stackTrace);
              if (await handleDeletedPath(part)) {
                continue;
              } else {
                deleteRecording(part.recordingId!);
                http.delete(
                    Uri(
                        scheme: 'https',
                        host: Config.host,
                        path: '/recordings/${recording.BEId}'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $jwt',
                    });
              }
            }
            rethrow;
          }
        }
        recording.sent = true;
        recording.sending = false;
        await updateRecording(recording);
        logger.i('Recording id ${recording.id} sent successfully.');
      } else {
        recording.sending = false;
        await updateRecording(recording);
        throw UploadException(
            'Failed to send recording to backend', response.statusCode);
      }
    } catch (e, stackTrace) {
      logger.e('Error sending recording: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recording.sending = false;
      await updateRecording(recording);
      rethrow;
    }
  }

  static Future<bool> handleDeletedPath(RecordingPart recordingPart) async {
    if (recordingPart.BEId != null) {
      final http.Response response = await http.get(
          Uri(
              scheme: 'https',
              host: Config.host,
              path:
                  '/recordings/part/${recordingPart.backendRecordingId}/${recordingPart.BEId}'),
          headers: {
            'Authorization':
                'Bearer ${await FlutterSecureStorage().read(key: 'token')}'
          });
      if (response.statusCode == 200) {
        logger.i(
            'Recording part id: ${recordingPart.id} found on backend, marking as sent.');
        Directory tempDir = await getApplicationDocumentsDirectory();
        final String partFilePath =
            '${tempDir.path}/recording_${recordingPart.backendRecordingId}_${recordingPart.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
        File file = await File(partFilePath).create();
        await file.writeAsBytes(response.bodyBytes);
        recordingPart.sent = true;
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
      }
    } else {
      return false;
      // deleteRecording(recordingPart.recordingId!);
      // http.delete(Uri(scheme: 'https', host: Config.host, path: '/recordings/${recordingPart.backendRecordingId}'),
      //     headers: {
      //       'Content-Type': 'application/json',
      //       'Authorization': 'Bearer ${await FlutterSecureStorage().read(key: 'token')}'}
      // );
      // return false;
    }
    return true;
  }

  static Future<int?> getRecordingBEIDbyID(int id) async {
    var db = await database;
    var value = await db.query("recordings", where: "id = ?", whereArgs: [id]);
    if (value.isNotEmpty) {
      return value.first["BEId"] as int?;
    } else {
      return null;
    }
  }

  /// Deletes a recording and its parts from the local cache.
  static Future<void> deleteRecordingFromCache(int id) async {
    final db = await database;
    // Delete associated part files
    for (final part in recordingParts.where((p) => p.recordingId == id)) {
      if (part.path != null) {
        try {
          await File(part.path!).delete();
        } catch (_) {
          // ignore file-system errors
        }
      }
    }
    // Remove associated parts from in-memory list and DB
    recordingParts.removeWhere((p) => p.recordingId == id);
    await db.delete(
      'recordingParts',
      where: 'recordingId = ?',
      whereArgs: [id],
    );
    // Delete main recording file
    Recording? rec;
    try {
      rec = recordings.firstWhere((r) => r.id == id);
    } catch (_) {
      rec = null;
    }
    if (rec != null && rec.path != null) {
      try {
        await File(rec.path!).delete();
      } catch (_) {
        // ignore file-system errors
      }
    }
    // Remove recording from in-memory list and DB
    recordings.removeWhere((r) => r.id == id);
    await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    logger.i('Recording id $id deleted from cache.');
  }

  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    // mark as sending
    recordingPart.sending = true;
    await updateRecordingPart(recordingPart);
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (recordingPart.dataBase64 == null) {
        throw UploadException('Recording part data is null', 410);
      }
      if (jwt == null) {
        throw UploadException('Failed to send recording part to backend', 401);
      }
      logger.i(
          'Uploading recording part (backendRecordingId: ${recordingPart.backendRecordingId}) with data length: ${recordingPart.dataBase64?.length}');
      // Retrieve the parent recording to obtain its backend ID
      // Recording? parentRecording = await getRecordingFromDbById(
      //     recordingPart.recordingId!);
      //recordingPart.backendRecordingId = parentRecording?.BEId ?? 0;
      // Database db = await database;
      // db.update('recordingParts', recordingPart.toJson(), where: 'id = ?',
      //     whereArgs: [recordingPart.id]);
      try {
        final Map<String, Object?> jsonBody = recordingPart.toBEJson();
        final http.Response response = await http.post(
          Uri(scheme: 'https', host: Config.host, path: '/recordings/part-new'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode(jsonBody),
        );
        if (response.statusCode == 200) {
          logger.i(response.body);
          int returnedId = jsonDecode(response.body);
          recordingPart.BEId = returnedId;
          recordingPart.sent = true;
          recordingPart.sending = false;
          await updateRecordingPart(recordingPart);
          logger.i(
              'Recording part id: ${recordingPart.id} uploaded successfully.');
        } else {
          // reset sending flag on failure
          recordingPart.sending = false;
          await updateRecordingPart(recordingPart);
          throw UploadException('Failed to upload part id: ${recordingPart.id}',
              response.statusCode);
        }
      } catch (e, stackTrace) {
        // reset sending flag on exception
        //logger.e('Error uploading part: $e' ,error: e, stackTrace: stackTrace);
        //Sentry.captureException(e, stackTrace: stackTrace);
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        rethrow;
      }
    } catch (e, stackTrace) {
      if (e is PathNotFoundException) {
        logger.e('Path not found for recording part id: ${recordingPart.id}',
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        rethrow;
      }
      // reset sending flag on exception
      logger.e('Error uploading part: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recordingPart.sending = false;
      await updateRecordingPart(recordingPart);
      rethrow;
    }
  }

  static Future<void> sendRecordingPartNew(RecordingPart recordingPart,
      {UploadProgress? onProgress}) async {
    if (await getRecordingPartById(recordingPart.id).sending) {
      logger.i('Recording part id: ${recordingPart.id} is already being sent.');
      return;
    }
    // mark as sending
    recordingPart.sending = true;
    await updateRecordingPart(recordingPart);
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (recordingPart.path == null) {
        throw UploadException('Recording part data is null', 410);
      }
      if (jwt == null) {
        throw UploadException('Failed to send recording part to backend', 401);
      }
      logger.i(
          'Uploading recording part (backendRecordingId: ${recordingPart.backendRecordingId}) with data length: ${recordingPart.dataBase64?.length}');
      final dio = Dio();

      // Do not let Dio auto-follow 30x on multipart posts, because it will
      // try to reuse the same finalized FormData stream.
      dio.options.followRedirects = false;
      dio.options.maxRedirects = 0;

      dio.options.contentType =
          null; // let FormData set multipart with boundary
      dio.options.headers['Authorization'] = 'Bearer $jwt';
      dio.options.headers['accept-encoding'] = 'identity';

      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          logger.i(
              'Dio request Content-Type: \'${options.headers['content-type'] ?? options.contentType}\'');
          logger.i(
              'Dio request headers (subset): ${options.headers.map((k, v) => MapEntry(k, k.toLowerCase() == 'authorization' ? '***' : v))}');
          handler.next(options);
        },
      ));

      // Build a fresh FormData every time we send or retry.
      FormData _buildFormData() => FormData.fromMap({
            'file': MultipartFile.fromFileSync(recordingPart.path!),
            'RecordingId': recordingPart.backendRecordingId,
            'StartDate': recordingPart.startTime.toIso8601String(),
            'EndDate': recordingPart.endTime.toIso8601String(),
            'GpsLatitudeStart': recordingPart.gpsLatitudeStart,
            'GpsLatitudeEnd': recordingPart.gpsLatitudeEnd,
            'GpsLongitudeStart': recordingPart.gpsLongitudeStart,
            'GpsLongitudeEnd': recordingPart.gpsLongitudeEnd,
          });

      final String initialUrl = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/part-new',
      ).toString();

      Response response = await dio.post(
        initialUrl,
        data: _buildFormData(),
        options: Options(
          validateStatus: (code) =>
              code != null && code < 400 ||
              (code != null && code >= 300 && code < 400),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            logger.i(
                'Upload progress: $sent / $total (${(sent / total * 100).toStringAsFixed(1)}%)');
          } else {
            logger.i('Upload progress: $sent bytes');
          }
          if (onProgress != null) onProgress(sent, total);
        },
      );

      // Handle a single manual redirect by rebuilding FormData.
      if (response.statusCode != null &&
          response.statusCode! >= 300 &&
          response.statusCode! < 400) {
        final loc = response.headers.value('location');
        if (loc != null && loc.isNotEmpty) {
          final redirectedUrl = Uri.parse(loc).isAbsolute
              ? loc
              : Uri.parse(initialUrl).resolve(loc).toString();
          logger.w(
              'Multipart POST received ${response.statusCode} redirect → $redirectedUrl. Retrying with fresh FormData.');

          response = await dio.post(
            redirectedUrl,
            data: _buildFormData(),
            options:
                Options(validateStatus: (code) => code != null && code < 500),
            onSendProgress: (sent, total) {
              if (total > 0) {
                logger.i(
                    'Upload progress (redirect): $sent / $total (${(sent / total * 100).toStringAsFixed(1)}%)');
              } else {
                logger.i('Upload progress (redirect): $sent bytes');
              }
              if (onProgress != null) onProgress(sent, total);
            },
          );
        }
      }

      if (response.statusCode == 200) {
        logger.i(response.data);
        int returnedId = response.data is int
            ? response.data
            : (response.data is String ? int.parse(response.data) : 0);
        recordingPart.BEId = returnedId;
        recordingPart.sent = true;
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        logger
            .i('Recording part id: ${recordingPart.id} uploaded successfully.');
      } else {
        // reset sending flag on failure
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        throw UploadException('Failed to upload part id: ${recordingPart.id}',
            response.statusCode!);
      }
    } catch (e, stackTrace) {
      if (e is PathNotFoundException) {
        logger.e('Path not found for recording part id: ${recordingPart.id}',
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        rethrow;
      }
      // reset sending flag on exception
      logger.e('Error uploading part: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recordingPart.sending = false;
      await updateRecordingPart(recordingPart);
      rethrow;
    }
  }

  static Future<void> updateRecording(Recording recording) async {
    try {
      int index = recordings.indexWhere((r) => r.id == recording.id);
      if (index != -1) {
        recordings[index] = recording;
      } else {
        recordings.add(recording);
      }
      final db = await database;
      await db.update('recordings', recording.toJson(),
          where: 'id = ?', whereArgs: [recording.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> updateRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      int index = recordingParts.indexWhere((r) => r.id == recordingPart.id);
      if (index != -1) {
        recordingParts[index] = recordingPart;
      } else {
        recordingParts.add(recordingPart);
      }
      await db.update('recordingParts', recordingPart.toJson(),
          where: 'id = ?', whereArgs: [recordingPart.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Update an existing recording on the backend
  /// Uses PATCH /recordings/[BEId]/edit
  static Future<void> updateRecordingBE(Recording recording) async {
    // Recording must already exist on backend
    if (recording.BEId == null) {
      logger.w('Cannot update recording on backend because BEId is null.');
      return;
    }

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw UploadException('Failed to update recording on backend', 401);
    }

    final Uri url = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/recordings/${recording.BEId}',
    );

    final http.Response response = await http.patch(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'name': recording.name,
        'note': recording.note,
        'estimatedBirdsCount': recording.estimatedBirdsCount,
        'device': recording.device,
      }),
    );

    if (response.statusCode == 200) {
      logger.i(
          'Recording BEId ${recording.BEId} successfully updated on backend.');
      // Keep local DB in sync
      await updateRecording(recording);
    } else {
      throw UploadException(
        'Failed to update recording on backend',
        response.statusCode,
      );
    }
  }

  static Future<void> fetchRecordingsFromBE() async {
    fetching = true;
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (jwt == null) {
        throw FetchException('Failed to fetch recordings from backend', 401);
      }
      // Read userId from secure storage instead of using email
      String? userId = await FlutterSecureStorage().read(key: 'userId');
      if (userId == null) {
        throw FetchException(
            'Failed to fetch recordings from backend: userId not found', 401);
      }
      Uri url = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings',
        query: 'parts=true&userId=$userId',
      );
      final http.Response response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      });
      if (response.statusCode == 200) {
        var body = json.decode(response.body);
        // email is not used anymore, but for backward compatibility, pass null
        List<Recording> recordings = List<Recording>.generate(body.length, (i) {
          return Recording.fromBEJson(body[i], null);
        });
        List<RecordingPart> parts = [];
        for (int i = 0; i < body.length; i++) {
          for (int j = 0; j < body[i]['parts'].length; j++) {
            RecordingPart part =
                RecordingPart.fromBEJson(body[i]['parts'][j], body[i]['id']);
            parts.add(part);

            logger.i('Added part with ID: ${part.id} and BEID: ${part.BEId}');
          }
        }
        fetchedRecordings = recordings;
        fetchedRecordingParts = parts;

        final db = await database;
        final List<Recording> localRecordings = await getRecordings();
        final Set<int?> beIds = recordings.map((r) => r.BEId).toSet();

        // Delete local recordings marked as sent but no longer present on backend
        for (var local in localRecordings) {
          if (local.sent && !beIds.contains(local.BEId)) {
            await deleteRecordingFromCache(local.id!);
            logger.i(
                'Recording id ${local.id} deleted locally (no longer on backend).');
          }
        }

        // Update any local recordings whose data mismatches backend
        for (var beRec in recordings) {
          try {
            var local = localRecordings.firstWhere((r) => r.BEId == beRec.BEId);
            bool needsUpdate = local.name != beRec.name ||
                local.note != beRec.note ||
                local.estimatedBirdsCount != beRec.estimatedBirdsCount ||
                local.device != beRec.device ||
                local.byApp != beRec.byApp;
            if (needsUpdate) {
              local.name = beRec.name;
              local.note = beRec.note;
              local.estimatedBirdsCount = beRec.estimatedBirdsCount;
              local.device = beRec.device;
              local.byApp = beRec.byApp;
              await updateRecording(local);
              logger
                  .i('Recording id ${local.id} updated to match backend data.');
            }
          } catch (_) {
            // no local match, skip
          }
        }
      } else if (response.statusCode == 204) {
        logger.i('No recordings found on backend.');
      } else {
        throw FetchException(
            'Failed to fetch recordings from backend', response.statusCode);
      }
    } finally {
      fetching = false;
    }
  }

  static Future<void> fetchFilteredPartsForRecordingsFromBE(
      List<Recording> recs,
      {bool verified = false}) async {
    fetchedFilteredRecordingParts = <FilteredRecordingPart>[];
    fetchedDetectedDialects = <DetectedDialect>[];

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    for (final rec in recs) {
      if (rec.BEId == null) continue;
      final uri = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/filtered',
        queryParameters: {
          'recordingId': '${rec.BEId}',
          'verified': verified ? 'true' : 'false',
        },
      );
      try {
        final resp = await http.get(uri, headers: {
          'Content-Type': 'application/json',
          if (jwt != null) 'Authorization': 'Bearer $jwt',
        });
        if (resp.statusCode == 200) {
          final List<dynamic> arr = json.decode(resp.body) as List<dynamic>;
          for (final item in arr) {
            if (item is! Map) continue;
            final map = (item as Map).cast<String, Object?>();
            final frp = FilteredRecordingPart.fromBEJson(map);
            fetchedFilteredRecordingParts!.add(frp);

            final dynList = map['detectedDialects'];
            if (dynList is List) {
              for (final d in dynList) {
                if (d is Map) {
                  final dd = DetectedDialect.fromBEJson(
                    (d as Map).cast<String, Object?>(),
                    parentFilteredPartBEID: frp.BEId ?? 0,
                  );
                  fetchedDetectedDialects!.add(dd);
                }
              }
            }
          }
        } else if (resp.statusCode == 204) {
          // none for this recording
        } else {
          logger.w(
              'Failed to fetch filtered parts for recording ${rec.BEId}: ${resp.statusCode}');
        }
      } catch (e, st) {
        logger.e('Error fetching filtered parts for recording ${rec.BEId}: $e',
            error: e, stackTrace: st);
        Sentry.captureException(e, stackTrace: st);
      }
    }
  }

  static Future<void> persistFetchedFilteredParts() async {
    if (fetchedFilteredRecordingParts == null ||
        fetchedFilteredRecordingParts!.isEmpty) return;

    // Build recording BEId -> local id map
    final localRecs = await getRecordings();
    final Map<int, int> recBeToLocal = {
      for (final r in localRecs)
        if (r.BEId != null && r.id != null) r.BEId!: r.id!
    };

    // Insert/update filtered parts first
    final Map<int, int> frpBeToLocal = <int, int>{};
    for (final frp in fetchedFilteredRecordingParts!) {
      if (frp.recordingBEID != null) {
        frp.recordingLocalId = recBeToLocal[frp.recordingBEID!];
      }
      if (frp.parentBEID != null && frpBeToLocal.containsKey(frp.parentBEID)) {
        frp.parentLocalId = frpBeToLocal[frp.parentBEID!];
      }
      final id = await insertFilteredRecordingPart(frp);
      if (frp.BEId != null && id > 0) {
        frpBeToLocal[frp.BEId!] = id;
      }
    }

    // Insert/update detected dialects, linked to local FRP ids
    if (fetchedDetectedDialects != null &&
        fetchedDetectedDialects!.isNotEmpty) {
      for (final dd in fetchedDetectedDialects!) {
        if (dd.filteredPartBEID != null &&
            frpBeToLocal.containsKey(dd.filteredPartBEID)) {
          dd.filteredPartLocalId = frpBeToLocal[dd.filteredPartBEID!];
        }
        await insertDetectedDialect(dd);
      }
    }
  }

  static Future<List<RecordingPart>> fetchPartsFromDbById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db
        .rawQuery("SELECT * FROM recordingParts WHERE RecordingId = $id");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<List<RecordingPart>> getPartsByRecordingId(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db
        .query("recordingParts", where: "recordingId = ?", whereArgs: [id]);
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<RecordingPart?> getRecordingPartByBEID(int id) async {
    final url = Uri(
        scheme: "https",
        host: Config.host,
        path: "/recordings/$id",
        query: "parts=true&sound=false");

    logger.i(url);

    try {
      final resp = await http.get(url);

      if (resp.statusCode == 200) {
        logger.i("sending req was succesfull");
        var part =
            RecordingPart.fromBEJson(json.decode(resp.body)['parts'][0], id);
        return part;
      } else {
        logger
            .i("req failed with statuscode ${resp.statusCode} -> ${resp.body}");
      }
    } catch (e) {
      return null;
    }
  }

  static Future<void> downloadRecording(int id) async {
    Recording? recording = await getRecordingFromDbById(id);
    if (recording == null) {
      throw FetchException('Recording not found in local database', 404);
    }
    if (recording.downloaded) return;

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }

    // Fetch all parts for this recording
    List<RecordingPart> parts = await getRecordingParts();
    Directory tempDir = await getApplicationDocumentsDirectory();
    List<String> paths = [];

    for (final part in parts.where((p) => p.recordingId == id)) {
      // Download each part's full sound
      final Uri url = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/part/${recording.BEId}/${part.BEId}/sound',
      );
      try {
        final http.Response response = await http.get(url, headers: {
          'Authorization': 'Bearer $jwt',
        });
        if (response.statusCode != 200) {
          throw FetchException(
              'Failed to download recording part: /recordings/part/${recording.BEId}/${part.BEId}/sound',
              response.statusCode);
        }
        // Save part to disk
        final String partFilePath =
            '${tempDir.path}/recording_${recording.BEId}_${part.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
        File file = await File(partFilePath).create();
        await file.writeAsBytes(response.bodyBytes);

        // Update part path and mark as sent
        part.path = partFilePath;
        part.sent = true;
        await updateRecordingPart(part);

        paths.add(partFilePath);
      } catch (e, stackTrace) {
        if (e is FetchException) {
          rethrow;
        } else {
          logger.e('Error downloading part BEID: ${part.BEId}: $e',
              error: e, stackTrace: stackTrace);
          Sentry.captureException(e, stackTrace: stackTrace);
        }
      }
    }

    logger.i('Dowloaded all parts');

    // Concatenate all parts into one file
    final String outputPath =
        '${tempDir.path}/recording_${recording.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
    await concatWavFiles(paths, outputPath);

    recording.path = outputPath;
    recording.downloaded = true;
    await updateRecording(recording);

    logger.i('Downloaded recording id: $id. File saved to: $outputPath');
  }

  static Future<void> concatRecordingParts(int recordingId) async {
    List<RecordingPart> parts = await getPartsByRecordingId(recordingId);
    if (parts.isEmpty) {
      logger.i('No parts found for recording id: $recordingId');
      return;
    }

    // Ensure parts are processed in chronological order
    parts.sort((a, b) => a.startTime.compareTo(b.startTime));

    final dir = await getApplicationDocumentsDirectory();
    final List<String> paths = [];

    for (final part in parts) {
      if (part.path != null) {
        // Re‑use the existing on‑disk file
        paths.add(part.path!);
      } else {
        logger.w('Part id: ${part.id} has no path on disk. Skipping.');
      }
    }

    if (paths.isEmpty) {
      logger.w('No valid parts found for recording id: $recordingId');
      return;
    }

    final String outputPath =
        '${dir.path}/recording_${DateTime.now().microsecondsSinceEpoch}.wav';

    try {
      await concatWavFiles(paths, outputPath);
    } catch (e, stackTrace) {
      logger.e('Failed to concatenate recording parts for id: $recordingId',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return;
    }

    logger.i('Supposed file path: $outputPath');

    final Recording recording =
        recordings.firstWhere((r) => r.id == recordingId);
    recording
      ..path = outputPath
      ..downloaded = true;
    await updateRecording(recording);

    logger.i(
        'Concatenated recording parts for id: $recordingId. File saved to: $outputPath');
  }

  static Future<Database> initDb() async {
    return openDatabase('soundNew.db', version: 11,
        onCreate: (Database db, int version) async {
      await db.execute('''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY,
        BEId INTEGER UNIQUE,
        mail TEXT,
        createdAt TEXT,
        estimatedBirdsCount INTEGER,
        device TEXT,
        byApp INTEGER,
        name TEXT,
        note TEXT,
        path TEXT,
        sent INTEGER,
        downloaded INTEGER,
        sending INTEGER,
        totalSeconds REAL,
        partCount INTEGER,
        env STRING DEFAULT \'prod\'
      )
      ''');
      await db.execute('''
      CREATE TABLE recordingParts(
        id INTEGER PRIMARY KEY,
        BEId INTEGER UNIQUE,
        recordingId INTEGER,
        backendRecordingId INTEGER,
        startTime TEXT,
        endTime TEXT,
        gpsLatitudeStart REAL,
        gpsLatitudeEnd REAL,
        gpsLongitudeStart REAL,
        gpsLongitudeEnd REAL,
        length INTEGER,
        path TEXT,
        square TEXT,
        sent INTEGER,
        sending INTEGER DEFAULT 0,
        FOREIGN KEY(recordingId) REFERENCES recordings(id)
      )
      ''');
      await db.execute('''
      CREATE TABLE images(
        id INTEGER PRIMARY KEY,
        recordingId INTEGER,
        path TEXT,
        sent INTEGER,
        FOREIGN KEY(recordingId) REFERENCES recordings(id)
      )
      ''');
      await db.execute('''
      CREATE TABLE Notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        type INTEGER NOT NULL,
        read INTEGER DEFAULT 0
      )
      ''');
      await db.execute('''
      CREATE TABLE Dialects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        BEID INTEGER UNIQUE,
        recordingId INTEGER,
        recordingBEID INTEGER,
        userGuessDialect TEXT,
        adminDialect TEXT,
        startDate TEXT,
        endDate TEXT
      )
      ''');
      await db.execute('''
    CREATE TABLE FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
    ''');

      await db.execute('''
    CREATE TABLE DetectedDialects(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
    ''');
    }, onOpen: (Database db) async {
      final String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (jwt == null) {
        logger.i('No JWT token found. Skipping loading recordings.');
        return;
      }
      final String email = JwtDecoder.decode(jwt)['sub'];
      final List<Map<String, dynamic>> recs =
          await db.query("recordings", where: "mail = ?", whereArgs: [email]);
      recordings =
          List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
      final List<Map<String, dynamic>> parts = await db.query("recordingParts");
      recordingParts =
          List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
      final List<Map<String, dynamic>> fparts =
          await db.query("FilteredRecordingParts");
      filteredRecordingParts = List.generate(
        fparts.length,
        (i) => FilteredRecordingPart.fromDb(fparts[i]),
      );

      final List<Map<String, dynamic>> ddRows =
          await db.query("DetectedDialects");
      detectedDialects = List.generate(
        ddRows.length,
        (i) => DetectedDialect.fromDb(ddRows[i]),
      );
      loadedRecordings = true;
    }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion <= 1) {
        // Add the new backendRecordingId column to recordingParts table
        await db.execute(
            'ALTER TABLE recordingParts ADD COLUMN backendRecordingId INTEGER;');
        await db.setVersion(2);
      }
      if (oldVersion <= 2) {
        logger.w(
            'Old version detected (<=2). Recreating entire database schema...');
        // Drop existing tables
        await db.execute('DROP TABLE IF EXISTS recordings;');
        await db.execute('DROP TABLE IF EXISTS recordingParts;');
        await db.execute('DROP TABLE IF EXISTS images;');
        await db.execute('DROP TABLE IF EXISTS Notifications;');
        await db.execute('DROP TABLE IF EXISTS Dialects;');

        // Recreate tables as defined in the onCreate callback
        await db.execute('''
          CREATE TABLE recordings(
            id INTEGER PRIMARY KEY,
            BEId INTEGER UNIQUE,
            mail TEXT,
            createdAt TEXT,
            estimatedBirdsCount INTEGER,
            device TEXT,
            byApp INTEGER,
            name TEXT,
            note TEXT,
            path TEXT,
            sent INTEGER,
            downloaded INTEGER,
            sending INTEGER
          )
        ''');
        await db.execute('''
            CREATE TABLE recordingParts(
            id INTEGER PRIMARY KEY,
            BEId INTEGER UNIQUE,
            recordingId INTEGER,
            backendRecordingId INTEGER,
            startTime TEXT,
            endTime TEXT,
            gpsLatitudeStart REAL,
            gpsLatitudeEnd REAL,
            gpsLongitudeStart REAL,
            gpsLongitudeEnd REAL,
            path TEXT,
            square TEXT,
            sent INTEGER,
            FOREIGN KEY(recordingId) REFERENCES recordings(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE images(
            id INTEGER PRIMARY KEY,
            recordingId INTEGER,
            path TEXT,
            sent INTEGER,
            FOREIGN KEY(recordingId) REFERENCES recordings(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE Notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            receivedAt TEXT NOT NULL,
            type INTEGER NOT NULL,
            read INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE Dialects (
            RecordingId INTEGER PRIMARY KEY AUTOINCREMENT,
            BEId INTEGER UNIQUE,
            dialectCode TEXT NOT NULL,
            StartDate TEXT NOT NULL,
            EndDate TEXT NOT NULL,
            FOREIGN KEY(RecordingId) REFERENCES recordings(id)
          )
        ''');
        await db.setVersion(newVersion);
      }
      // Upgrade from v3 → v4: add the 'sending' column to recordingParts
      if (oldVersion <= 3) {
        await db.execute(
            'ALTER TABLE recordingParts ADD COLUMN sending INTEGER DEFAULT 0;');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 4) {
        await db.execute(
            'ALTER TABLE Dialects RENAME COLUMN dialect TO dialectCode;');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 5) {
        try {
          await db
              .execute('ALTER TABLE recordingParts ADD COLUMN length INTEGER;');
        } catch (e, stackTrace) {
          logger.w('Failed to add length column to recordingParts: $e',
              error: e, stackTrace: stackTrace);
          Sentry.captureException(e, stackTrace: stackTrace);
        }
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 6) {
        await db.execute('DROP TABLE IF EXISTS Dialects;');
        await db.execute('''
          CREATE TABLE Dialects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            BEID INTEGER UNIQUE,
            recordingId INTEGER,
            recordingBEID INTEGER,
            userGuessDialect TEXT,
            adminDialect TEXT,
            startDate TEXT,
            endDate TEXT
          )
        ''');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 7) {
        await db.execute('''
    CREATE TABLE IF NOT EXISTS FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
  ''');
        await db.execute('''
    CREATE TABLE IF NOT EXISTS DetectedDialects(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
  ''');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 8) {
        await db
            .execute('ALTER TABLE recordings ADD COLUMN partCount INTEGER;');
        await db.execute('''UPDATE recordings AS r
            SET partCount = COALESCE((
            SELECT COUNT(*)
        FROM recordingParts AS p
        WHERE p.recordingId = r.id
          ), 0);''');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 9) {
        await db.execute(
            'ALTER TABLE recordings ADD COLUMN env STRING DEFAULT \'prod\';');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 10) {
        await db
            .execute('ALTER TABLE recordings ADD COLUMN totalSeconds REAL;');

        await fetchAndUpdateDurationsFromBackend(DatabaseNew());
        await updateAllRecordingsDurations(DatabaseNew());
        await db.setVersion(newVersion);
      }
    });
  }

  static Future<bool> hasInternetAccess() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  static Future<void> insertNotification(RemoteMessage message) async {
    final db = await database;
    await db.insert('Notifications', {
      'title': message.notification?.title,
      'type': int.parse(message.messageType!),
      'body': message.notification?.body,
      'receivedAt': DateTime.now().toIso8601String(),
    });
  }

  // New helper method to insert a custom local notification.
  static Future<void> sendLocalNotification(
      String title, String message) async {
    final String fcmToken =
        ((await FlutterSecureStorage().read(key: 'fcmToken'))) ?? '';
    if (fcmToken == '') {
      logger.w("Failed to send local notification: FCM token is empty");
      return;
    }
    await sendPushNotificationDirectly(fcmToken, title, message);
    // final db = await database;
    // await db.insert('Notifications', {
    //   'title': title,
    //   'body': message,
    //   'receivedAt': DateTime.now().toIso8601String(),
    //   'type': 0, // 0 for local notifications
    //   'read': 0,
    // });
    // logger.i("Local notification inserted: $title - $message");
  }

  static Future<List<NotificationItem>> getNotificationList() async {
    final db = await database;
    final List<Map<String, dynamic>> notifications =
        await db.query('Notifications');
    List<NotificationItem> messages = [];
    for (Map<String, dynamic> notification in notifications) {
      messages.add(NotificationItem(
        title: notification['title'],
        message: notification['body'],
        time: notification['receivedAt'],
        unread: notification['read'] == 0,
      ));
    }
    return messages;
  }

  static Future<Recording?> getRecordingFromDbById(int recordingId) async {
    final db = await database;
    final String? email = JwtDecoder.decode(
        (await FlutterSecureStorage().read(key: 'token'))!)['sub'];
    final List<Map<String, dynamic>> results = await db.query("recordings",
        where: "id = ? AND mail = ? AND env = ?",
        whereArgs: [
          recordingId,
          email,
          Config.hostEnvironment.name.toString()
        ]);
    if (results.isNotEmpty) {
      return Recording.fromJson(results.first);
    }
    return null;
  }

  /// Checks whether *all* parts of the given recording have been sent.
  /// Throws [UnsentPartsException] if any part remains unsent.
  static Future<void> checkRecordingPartsSent(int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where: 'recordingId = ? AND sent = ?',
      whereArgs: [recordingId, 0],
    );
    if (unsent.isNotEmpty) {
      throw UnsentPartsException();
    }
  }

  /// Attempts to resend any recording parts that were not sent previously.
  static Future<void> resendUnsentParts() async {
    final db = await database;
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where: 'sent = ?',
      whereArgs: [0],
    );
    for (final partMap in unsent) {
      try {
        RecordingPart part = RecordingPart.fromJson(partMap);
        part.sending = true;
        await updateRecordingPart(part);
        await sendRecordingPartNew(part);
      } catch (e, stackTrace) {
        logger.e('Failed to resend recording part id: ${partMap['id']}',
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
  }

  // Dialects
  static Future<int> insertDialect(Dialect dialect) async {
    final db = await database;

    logger.i('dialect: ${dialect.toJson()}');
    int id = await db.insert("Dialects", dialect.toJson());
    logger.i('Dialect ${dialect.id} inserted.');
    return id;
  }

  static Future<void> updateDialect(Dialect dialect) async {
    final db = await database;
    await db.update("Dialects", dialect.toJson(),
        where: "id = ?", whereArgs: [dialect.id]);
    logger.i('Dialect ${dialect.id} updated.');
  }

  static Future<void> deleteDialect(int id) async {
    final db = await database;
    await db.delete("Dialects", where: "id = ?", whereArgs: [id]);
    logger.i('Dialect $id deleted.');
  }

  static Future<List<Dialect>> getDialectsByRecordingId(int recordingId) async {
    logger.i('Loading dialects for recording: $recordingId');
    final db = await database;
    final List<Map<String, dynamic>> results = await db
        .query("Dialects", where: "recordingId = ?", whereArgs: [recordingId]);
    if (results.isEmpty) {
      logger.i('No dialects found for recording: $recordingId');
      return [];
    }
    return List.generate(results.length, (i) => Dialect.fromJson(results[i]));
  }

  static Future<List<Dialect>> getDialectsByRecordingBEID(
      int recordingBEID) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query("Dialects",
        where: "recordingBEID = ?", whereArgs: [recordingBEID]);
    return List.generate(results.length, (i) => Dialect.fromJson(results[i]));
  }

  // === Filtered Recording Parts CRUD ===
  static Future<int> insertFilteredRecordingPart(
      FilteredRecordingPart frp) async {
    final db = await database;
    if (frp.BEId != null) {
      final existing = await db.query('FilteredRecordingParts',
          where: 'BEId = ?', whereArgs: [frp.BEId], limit: 1);
      if (existing.isNotEmpty) {
        frp.id = existing.first['id'] as int?;
        await db.update('FilteredRecordingParts', frp.toDbJson(),
            where: 'id = ?', whereArgs: [frp.id]);
        final idx = filteredRecordingParts.indexWhere((e) => e.id == frp.id);
        if (idx != -1)
          filteredRecordingParts[idx] = frp;
        else
          filteredRecordingParts.add(frp);
        return frp.id ?? -1;
      }
    }
    final id = await db.insert('FilteredRecordingParts', frp.toDbJson());
    frp.id = id;
    filteredRecordingParts.add(frp);
    return id;
  }

  static Future<void> updateFilteredRecordingPart(
      FilteredRecordingPart frp) async {
    final db = await database;
    await db.update('FilteredRecordingParts', frp.toDbJson(),
        where: 'id = ?', whereArgs: [frp.id]);
    final idx = filteredRecordingParts.indexWhere((e) => e.id == frp.id);
    if (idx != -1)
      filteredRecordingParts[idx] = frp;
    else
      filteredRecordingParts.add(frp);
  }

// === Detected Dialects CRUD ===
  static Future<int> insertDetectedDialect(DetectedDialect dd) async {
    final db = await database;
    if (dd.BEId != null) {
      final existing = await db.query('DetectedDialects',
          where: 'BEId = ?', whereArgs: [dd.BEId], limit: 1);
      if (existing.isNotEmpty) {
        dd.id = existing.first['id'] as int?;
        await db.update('DetectedDialects', dd.toDbJson(),
            where: 'id = ?', whereArgs: [dd.id]);
        final idx = detectedDialects.indexWhere((e) => e.id == dd.id);
        if (idx != -1)
          detectedDialects[idx] = dd;
        else
          detectedDialects.add(dd);
        return dd.id ?? -1;
      }
    }
    final id = await db.insert('DetectedDialects', dd.toDbJson());
    dd.id = id;
    detectedDialects.add(dd);
    return id;
  }

  static Future<void> updateDetectedDialect(DetectedDialect dd) async {
    final db = await database;
    await db.update('DetectedDialects', dd.toDbJson(),
        where: 'id = ?', whereArgs: [dd.id]);
    final idx = detectedDialects.indexWhere((e) => e.id == dd.id);
    if (idx != -1)
      detectedDialects[idx] = dd;
    else
      detectedDialects.add(dd);
  }

  /// Representative dialects for a local recording (prefers confirmed, else user guess)
  static Future<List<String>> getRepresentativeDialectCodesForRecording(
      int recordingLocalId) async {
    final db = await database;
    final rows = await db.rawQuery('''
    SELECT DISTINCT COALESCE(dd.confirmedDialect, dd.userGuessDialect) AS code
    FROM FilteredRecordingParts frp
    JOIN DetectedDialects dd ON dd.filteredPartLocalId = frp.id
    WHERE frp.recordingLocalId = ?
      AND frp.representant = 1
      AND COALESCE(dd.confirmedDialect, dd.userGuessDialect) IS NOT NULL
      AND COALESCE(dd.confirmedDialect, dd.userGuessDialect) <> ''
  ''', [recordingLocalId]);

    final codes = rows
        .map((r) => (r['code'] as String).trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return codes.isEmpty ? <String>['Neurceno'] : codes;
  }

  static getRecordingPartById(recordingId) {
    return recordingParts.firstWhere((part) => part.id == recordingId);
  }
}
