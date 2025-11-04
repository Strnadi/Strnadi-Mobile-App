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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:strnadi/config/config.dart';
import 'package:strnadi/exceptions.dart';

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