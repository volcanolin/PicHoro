import 'package:dio/dio.dart';
import 'package:horopic/utils/common_functions.dart';
import 'package:path/path.dart' as my_path;

/// CloudFlare-ImgBed (https://github.com/MarSeventh/CloudFlare-ImgBed) upload/delete API.
class CfimgbedImageUploadUtils {
  static String _normalizeHost(String host) {
    host = host.trim();
    if (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      host = 'https://$host';
    }
    return host;
  }

  static String _manageToken(Map configMap) {
    final token = (configMap['apiToken'] ?? '').toString().trim();
    if (token.isNotEmpty) return token;
    return (configMap['authCode'] ?? '').toString().trim();
  }

  static Map<String, String> _authHeaders(Map configMap, {bool forManage = false}) {
    final headers = <String, String>{};
    if (forManage) {
      final token = _manageToken(configMap);
      if (token.isNotEmpty) {
        headers['Authorization'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
      }
    }
    return headers;
  }

  /// Returns [success, formatedURL, returnUrl, pictureKey]
  static Future<List<String>> uploadApi({
    required String path,
    required String name,
    required Map configMap,
    Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final host = _normalizeHost(configMap['host']?.toString() ?? '');
      final authCode = (configMap['authCode'] ?? '').toString().trim();
      final uploadChannel = (configMap['uploadChannel'] ?? 'telegram').toString().trim();
      final uploadFolder = (configMap['uploadFolder'] ?? '').toString().trim();
      final channelName = (configMap['channelName'] ?? '').toString().trim();
      final apiToken = (configMap['apiToken'] ?? '').toString().trim();

      if (host.isEmpty) {
        return ['failed'];
      }

      final query = <String, dynamic>{
        'returnFormat': 'full',
        'uploadChannel': uploadChannel.isEmpty ? 'telegram' : uploadChannel,
      };
      if (authCode.isNotEmpty) {
        query['authCode'] = authCode;
      }
      if (uploadFolder.isNotEmpty) {
        query['uploadFolder'] = uploadFolder;
      }
      if (channelName.isNotEmpty) {
        query['channelName'] = channelName;
      }

      final formdata = FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: my_path.basename(name)),
      });

      final options = setBaseOptions();
      options.headers = {
        'Content-Type': 'multipart/form-data',
        if (apiToken.isNotEmpty) 'Authorization': apiToken.startsWith('Bearer ') ? apiToken : 'Bearer $apiToken',
      };

      final dio = Dio(options);
      final response = await dio.post(
        '$host/upload',
        queryParameters: query,
        data: formdata,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200 && response.data is List && (response.data as List).isNotEmpty) {
        final item = response.data[0];
        if (item is! Map) {
          return ['failed'];
        }
        String returnUrl = (item['publicUrl'] ?? item['src'] ?? '').toString();
        if (returnUrl.isEmpty) {
          return ['failed'];
        }
        if (returnUrl.startsWith('/')) {
          returnUrl = '$host$returnUrl';
        }
        // pictureKey for delete API: path after /file/ or relative path without leading slash
        String pictureKey = (item['src'] ?? '').toString();
        if (pictureKey.startsWith('/file/')) {
          pictureKey = pictureKey.substring('/file/'.length);
        } else if (pictureKey.startsWith('file/')) {
          pictureKey = pictureKey.substring('file/'.length);
        } else if (pictureKey.startsWith('/')) {
          pictureKey = pictureKey.substring(1);
        }
        if (pictureKey.isEmpty) {
          // fallback: last path segment of URL
          pictureKey = Uri.parse(returnUrl).pathSegments.isNotEmpty
              ? Uri.parse(returnUrl).pathSegments.where((e) => e.isNotEmpty).join('/')
              : my_path.basename(name);
          if (pictureKey.startsWith('file/')) {
            pictureKey = pictureKey.substring(5);
          }
        }

        final formatedURL = getFormatedUrl(returnUrl, name);
        return ['success', formatedURL, returnUrl, pictureKey];
      }

      flogErr(
        response,
        {'path': path, 'name': name, 'status': response.statusCode, 'data': response.data},
        'CfimgbedImageUploadUtils',
        'uploadApi',
      );
      return ['failed'];
    } catch (e) {
      flogErr(e, {'path': path, 'name': name}, 'CfimgbedImageUploadUtils', 'uploadApi');
      return ['failed'];
    }
  }

  static Future<List<String>> deleteApi({required Map deleteMap, required Map configMap}) async {
    try {
      final host = _normalizeHost(configMap['host']?.toString() ?? '');
      final pictureKey = (deleteMap['pictureKey'] ?? '').toString();
      if (host.isEmpty || pictureKey.isEmpty) {
        return ['failed'];
      }

      // API: GET /api/manage/delete/{path}
      final encodedPath = pictureKey.split('/').map(Uri.encodeComponent).join('/');
      final options = setBaseOptions();
      options.headers = _authHeaders(configMap, forManage: true);

      final dio = Dio(options);
      final response = await dio.get('$host/api/manage/delete/$encodedPath');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['success'] == true) {
          return ['success'];
        }
        // some deployments may return plain text
        if (data is String && data.toLowerCase().contains('success')) {
          return ['success'];
        }
        if (data is Map && data['error'] == null) {
          return ['success'];
        }
      }
      flogErr(
        response,
        {'deleteMap': deleteMap, 'configMap': configMap},
        'CfimgbedImageUploadUtils',
        'deleteApi',
      );
      return ['failed'];
    } catch (e) {
      flogErr(e, {'deleteMap': deleteMap, 'configMap': configMap}, 'CfimgbedImageUploadUtils', 'deleteApi');
      return ['failed'];
    }
  }
}
