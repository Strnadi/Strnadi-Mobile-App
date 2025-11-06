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
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../database/databaseNew.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:strnadi/config/config.dart';
import 'package:logger/logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/PostRecordingForm/addDialect.dart';

import 'dialect_keyword_translator.dart';

Logger logger = Logger();

class Dialect{
  int? id; // Unique identifier for the dialect
  int? BEID; // Backend identifier for the dialect
  int? recordingId; // Identifier for the associated recording
  int? recordingBEID; // Identifier for the recording in the backend
  String? userGuessDialect;
  String? adminDialect;
  DateTime startDate; // Start date of the dialect
  DateTime endDate; // End date of the dialect

  // Constructor
  Dialect({
    required this.id,
    this.BEID,
    this.recordingId,
    this.recordingBEID,
    String? userGuessDialect,
    String? adminDialect,
    required this.startDate,
    required this.endDate,
  })  : userGuessDialect =
            DialectKeywordTranslator.toEnglish(userGuessDialect),
        adminDialect = DialectKeywordTranslator.toEnglish(adminDialect);

  factory Dialect.fromJson(Map<String, dynamic> json) { //From DB Json
    return Dialect(
      id: json['id'],
      BEID: json['BEID'],
      recordingId: json['recordingId'],
      recordingBEID: json['recordingBEID'],
      userGuessDialect: json['userGuessDialect'],
      adminDialect: json['adminDialect'],
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
    );
  }

  factory Dialect.fromBEJson(Map<String, dynamic> json, int? recordingId, int? recordingBEID, DateTime startDate, DateTime endDate){ // From BE Json
    return Dialect(
      id: null,
      BEID: json['id'],
      recordingId: recordingId,
      recordingBEID: recordingBEID,
      userGuessDialect: json['userGuessDialect'],
      adminDialect: json['confirmedDialect'],
      startDate: startDate,
      endDate: endDate,
    );
  }

  Map<String, dynamic> toJson() { // To DB Json
    return {
      'id': id,
      'BEID': BEID,
      'recordingId': recordingId,
      'recordingBEID': recordingBEID,
      'userGuessDialect': DialectKeywordTranslator.toEnglish(userGuessDialect),
      'adminDialect': DialectKeywordTranslator.toEnglish(adminDialect),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
    };
  }

  Map<String, dynamic> toBEJson() {
    // To BE Json
    return {
      'recordingId': recordingBEID,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'dialectCode': DialectKeywordTranslator.toEnglish(userGuessDialect),
    };
  }
  get dialect {
    return DialectKeywordTranslator.toLocalized(adminDialect ?? 'Unassessed');
  }

  String? get userGuessDialectLocalized =>
      userGuessDialect == null
          ? null
          : DialectKeywordTranslator.toLocalized(userGuessDialect!);
}

List<Dialect> dialectsFromBEJson(List<dynamic> json, {int? recordingId}) {
  logger.i('Loading dialects from BE JSON');
  logger.t(json.toString());
  final List<Dialect> dialects = [];

  for (Map<String, dynamic> recording in json) {
    final int recordingBEID = recording['recordingId'];
    final DateTime startDate = DateTime.parse(recording['startDate']);
    final DateTime endDate = DateTime.parse(recording['endDate']);

    final List<dynamic> detectedDialects = recording['detectedDialects'] ?? [];
    for (var dialect in detectedDialects) {
      dialects.add(
        Dialect.fromBEJson(
          dialect,
          recordingId,
          recordingBEID,
          startDate,
          endDate,
        ),
      );
    }
  }
  logger.i('Loaded dialects from BE JSON');
  logger.t(dialects);
  return dialects;
}

Future<void> insertDialects(List <Dialect> dialects) async {
  for (Dialect dialect in dialects) {
    await DatabaseNew.insertDialect(dialect);
  }
}

Future<List<Dialect>> fetchRecordingDialects(int? recordingBEID) async {
  logger.i('Loading dialects for recording: ${recordingBEID}');
  http.Response response;
  try {
    final String jwt = await FlutterSecureStorage().read(key: 'token') ?? '';
    final Uri url = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/filtered');
    if (recordingBEID!=null){
      url.replace(query: 'recordingId=$recordingBEID');
    }
    response = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt'
    },);
  }
  catch(e, stackTrace){
    logger.e('Failed to load dialects for recording: $recordingBEID :$e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    return [];
  }
  try {
    if (response.statusCode == 200) {
      logger.i('Loaded dialects for recording: $recordingBEID');
      return dialectsFromBEJson(json.decode(response.body));
    }
    else {
      logger.e('Failed to load $recordingBEID dialects: ${response.statusCode} | ${response.body}');
      return [];
    }
  }
  catch(e, stackTrace){
    logger.e('Failed to load $recordingBEID dialects: $e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    return [];
  }
}

DialectModel ToDialectModel(Dialect dialect) {
  final Map<String, Color> dialectColors = {
    'BC': Colors.yellow,
    'BE': Colors.green,
    'BlBh': Colors.lightBlue,
    'BhBl': Colors.blue,
    'XB': Colors.red,
    'Other': Colors.white,
    "I don't know": Colors.grey.shade300,
    'Unknown': Colors.grey.shade500,
    'Unassessed': Colors.grey.shade400,
    'Undetermined': Colors.grey.shade400,
    'No Dialect': Colors.black,
  };
  final String englishType =
      DialectKeywordTranslator.toEnglish(dialect.adminDialect) ??
          dialect.adminDialect ??
          'Unassessed';
  final String displayLabel = DialectKeywordTranslator.toLocalized(englishType);

  return DialectModel(
    label: displayLabel,
    startTime: Duration(
    milliseconds: dialect.startDate.millisecondsSinceEpoch).inSeconds
        .toDouble(),
    endTime: Duration(milliseconds: dialect.endDate.millisecondsSinceEpoch)
        .inSeconds.toDouble(),
    type: englishType,
    color: dialectColors[englishType] ?? Colors.white,
    );
}
