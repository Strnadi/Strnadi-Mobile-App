import 'dart:convert';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/logging/api_diagnostics.dart';

void main() {
  ApiDiagnostics parse(
    Object? payload, {
    int status = 422,
  }) => ApiDiagnostics.fromResponse(
    method: 'POST',
    uri: Uri.parse(
      'https://user:secret@example.test/recordings?lat=50&token=hidden#secret',
    ),
    statusCode: status,
    payload: payload,
    durationMs: 12,
    requestId: 'request-1',
  );

  test(
    'extracts nested error reason and correlation without retaining bodies',
    () {
      final result = parse({
        'error': {
          'code': 'invalid_viewport',
          'reason': 'bounds_inverted',
          'message': 'North must exceed south',
        },
        'traceId': 'trace-1',
        'token': 'private-secret',
        'largeUnrelatedData': ['not retained'],
      });
      expect(result.errorCode, 'invalid_viewport');
      expect(result.reason, 'bounds_inverted');
      expect(result.message, 'North must exceed south');
      expect(result.traceId, 'trace-1');
      expect(result.statusCode, 422);
      expect(result.durationMs, 12);
      expect(result.endpoint, 'https://example.test/recordings');
      expect(result.toContext().toString(), isNot(contains('private-secret')));
      expect(result.toContext().toString(), isNot(contains('not retained')));
    },
  );

  test('accepts OAuth JSON string and byte response bodies', () {
    const payload =
        '{"error":"invalid_grant","error_description":"Grant has expired"}';
    for (final body in <Object>[payload, utf8.encode(payload)]) {
      final result = parse(body, status: 400);
      expect(result.errorCode, 'invalid_grant');
      expect(result.reason, 'Grant has expired');
    }
  });

  test('accepts problem details and validation arrays', () {
    final problem = parse({
      'problem': {
        'type': 'invalid_request',
        'title': 'Invalid request',
        'detail': 'Review the submitted fields',
      },
    });
    expect(problem.reason, 'Invalid request');
    expect(problem.message, 'Review the submitted fields');
    final validation = parse({
      'errors': {
        'Name': ['Name is required'],
        'Length': ['Length must be positive'],
      },
    });
    expect(validation.reason, 'Name is required; Length must be positive');
  });

  test(
    'uses deterministic reasons for absent malformed binary and large data',
    () {
      for (final body in <Object?>[
        null,
        '',
        '<html>private server page</html>',
        '{broken',
        [255, 0, 1],
        'x' * (ApiDiagnostics.maximumBodyBytes + 1),
      ]) {
        final result = parse(body, status: 503);
        expect(result.reason, 'Service unavailable');
        expect(result.message, isNull);
      }
    },
  );

  test('bounds and sanitizes individual diagnostic fields', () {
    final result = parse({
      'reason': 'Authorization: Bearer private-token\n${'x' * 400}',
      'detail': 'Contact bird@example.test',
    });
    expect(result.reason.length, lessThanOrEqualTo(200));
    expect(result.reason, isNot(contains('\n')));
    expect(result.reason, isNot(contains('private-token')));
    expect(result.message, isNot(contains('bird@example.test')));
  });

  test('does not inspect successful binary payloads', () {
    final result = parse(_UnreadableBytes(), status: 200);
    expect(result.reason, 'Request completed');
    expect(result.message, isNull);
  });

  test('bounds a long endpoint made of individually short path segments', () {
    final result = ApiDiagnostics.fromResponse(
      method: 'GET',
      uri: Uri.parse(
        'https://example.test/${List.filled(30, 'recordings').join('/')}?token=private',
      ),
      statusCode: 500,
    );
    expect(result.endpoint.length, ApiDiagnostics.maximumFieldLength);
    expect(result.endpoint, endsWith('...'));
    expect(result.endpoint, startsWith('https://example.test/recordings/'));
    expect(result.endpoint, isNot(contains('private')));
  });
}

class _UnreadableBytes extends ListBase<int> {
  @override
  int get length => throw StateError('Success audio was inspected');
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  int operator [](int index) => throw StateError('Success audio was inspected');
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('immutable');
}
