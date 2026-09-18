import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';

class HealthController {
  const HealthController();

  Dio get _dio => ApiDioClient.instance;

  Future<Response<dynamic>> checkBackendHealth({required String host}) {
    final uri = ApiDioClient.uri('/utils/health', host: host);
    return _dio.headUri(
      uri,
      options: Options(extra: const <String, Object>{'authRequired': false}),
    );
  }
}
