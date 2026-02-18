import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class RecordingPartsController {
  const RecordingPartsController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path, {Map<String, dynamic>? queryParameters}) {
    return Uri(
      scheme: 'https',
      host: Config.host,
      path: path,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  Future<Response<dynamic>> uploadRecordingPartJson(Map<String, Object?> body) {
    return _dio.postUri(
      _uri('/recordings/part-new'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> uploadRecordingPartMultipart({
    required String filePath,
    required int? backendRecordingId,
    required DateTime startDate,
    required DateTime endDate,
    required double? gpsLatitudeStart,
    required double? gpsLatitudeEnd,
    required double? gpsLongitudeStart,
    required double? gpsLongitudeEnd,
    ProgressCallback? onSendProgress,
    String? overrideUrl,
  }) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromFileSync(filePath),
      'RecordingId': backendRecordingId,
      'StartDate': startDate.toIso8601String(),
      'EndDate': endDate.toIso8601String(),
      'GpsLatitudeStart': gpsLatitudeStart,
      'GpsLatitudeEnd': gpsLatitudeEnd,
      'GpsLongitudeStart': gpsLongitudeStart,
      'GpsLongitudeEnd': gpsLongitudeEnd,
    });

    final String requestUrl =
        overrideUrl ?? _uri('/recordings/part-new').toString();

    return _dio.post<dynamic>(
      requestUrl,
      data: formData,
      options: Options(
        contentType: null,
        headers: const {'accept-encoding': 'identity'},
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
      ),
      onSendProgress: onSendProgress,
    );
  }

  Future<Response<dynamic>> fetchPart(
    int backendRecordingId,
    int backendPartId,
  ) {
    return _dio.getUri(
      _uri('/recordings/part/$backendRecordingId/$backendPartId'),
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<Response<List<int>>> downloadPartSound(
    int backendRecordingId,
    int backendPartId, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return _dio.get<List<int>>(
      _uri('/recordings/part/$backendRecordingId/$backendPartId/sound')
          .toString(),
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
