import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/api/services/recording_detail_api_service.dart';

class FakeController extends FilteredRecordingsController {
  int status = 200;
  dynamic payload;
  int? requestedId;
  bool? requestedVerified;
  String? requestedHost;

  @override
  Future<Response<dynamic>> fetchFilteredParts({
    int? recordingId,
    bool? verified,
    String? accessToken,
    String? host,
  }) async {
    requestedId = recordingId;
    requestedVerified = verified;
    requestedHost = host;
    return Response(
      statusCode: status,
      data: payload,
      requestOptions: RequestOptions(path: '/recordings/filtered'),
    );
  }
}

void main() {
  test(
    'detail service pins backend ID and host, decodes list, skips invalid rows',
    () async {
      final controller = FakeController()
        ..payload = jsonEncode([
          {'id': 1},
          null,
          7,
        ]);
      final api = RecordingDetailApiService(controller: controller);
      expect(await api.fetchDialectParts(700, host: 'preprod.example.test'), [
        {'id': 1},
      ]);
      expect(controller.requestedId, 700);
      expect(controller.requestedVerified, isFalse);
      expect(controller.requestedHost, 'preprod.example.test');
    },
  );

  test(
    'empty and malformed responses preserve empty/error distinctions',
    () async {
      final controller = FakeController()..status = 204;
      final api = RecordingDetailApiService(controller: controller);
      expect(
        await api.fetchDialectParts(700, host: 'api.example.test'),
        isEmpty,
      );
      controller.status = 200;
      controller.payload = {'unexpected': 'object'};
      expect(
        await api.fetchDialectParts(700, host: 'api.example.test'),
        isEmpty,
      );
      controller.payload = '{invalid';
      await expectLater(
        api.fetchDialectParts(700, host: 'api.example.test'),
        throwsFormatException,
      );
      controller.status = 503;
      await expectLater(
        api.fetchDialectParts(700, host: 'api.example.test'),
        throwsException,
      );
    },
  );
}
