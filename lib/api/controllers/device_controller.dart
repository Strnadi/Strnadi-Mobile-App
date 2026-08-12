import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';

class DeviceController {
  const DeviceController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String host, String path) {
    return Uri(
      scheme: 'https',
      host: host,
      path: path,
    );
  }

  Options _authorizedOptions(String accessToken) {
    return Options(
      contentType: Headers.jsonContentType,
      followRedirects: false,
      maxRedirects: 0,
      headers: <String, Object>{
        'Authorization': 'Bearer $accessToken',
      },
      extra: const <String, Object>{'authRequired': false},
    );
  }

  Future<Response<dynamic>> addDevice(
    Map<String, dynamic> body, {
    required String host,
    required String accessToken,
  }) {
    return _dio.postUri(
      _uri(host, '/devices/add'),
      data: body,
      options: _authorizedOptions(accessToken),
    );
  }

  Future<Response<dynamic>> updateDevice(
    Map<String, dynamic> body, {
    required String host,
    required String accessToken,
  }) {
    return _dio.patchUri(
      _uri(host, '/devices/update'),
      data: body,
      options: _authorizedOptions(accessToken),
    );
  }

  Future<Response<dynamic>> deleteDeviceToken(
    String token, {
    required String host,
    required String accessToken,
  }) {
    return _dio.deleteUri(
      _uri(host, '/devices/delete/$token'),
      options: _authorizedOptions(accessToken),
    );
  }
}
