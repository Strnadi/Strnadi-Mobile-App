import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class DeviceController {
  const DeviceController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path) {
    return Uri(
      scheme: 'https',
      host: Config.host,
      path: path,
    );
  }

  Future<Response<dynamic>> addDevice(Map<String, dynamic> body) {
    return _dio.postUri(
      _uri('/devices/add'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> updateDevice(Map<String, dynamic> body) {
    return _dio.patchUri(
      _uri('/devices/update'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> deleteDeviceToken(String token) {
    return _dio.deleteUri(
      _uri('/devices/delete/$token'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
