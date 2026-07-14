import 'package:dio/dio.dart';
import 'package:horopic/picture_host_manage/common/base_manage_api.dart';
import 'package:horopic/utils/common_functions.dart';
import 'package:path/path.dart' as my_path;
import 'package:path_provider/path_provider.dart';

/// Manage API for CloudFlare-ImgBed.
///
/// Note: list/delete endpoints require admin auth or an API Token with the
/// corresponding permission. Upload authCode alone may not be enough unless
/// the server has no admin credentials configured.
class CfimgbedManageAPI extends BaseManageApi {
  static final CfimgbedManageAPI _instance = CfimgbedManageAPI._internal();

  CfimgbedManageAPI._internal();

  factory CfimgbedManageAPI() => _instance;

  @override
  String configFileName() => 'cfimgbed_config.txt';

  String _normalizeHost(String host) {
    host = host.trim();
    if (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      host = 'https://$host';
    }
    return host;
  }

  Future<Map> _safeConfig() async {
    try {
      final map = await getConfigMap();
      return map;
    } catch (e) {
      return {};
    }
  }

  String _manageToken(Map configMap) {
    final token = (configMap['apiToken'] ?? '').toString().trim();
    if (token.isNotEmpty) return token;
    return (configMap['authCode'] ?? '').toString().trim();
  }

  Future<Dio> _dio({bool forManage = true}) async {
    final configMap = await _safeConfig();
    final options = setBaseOptions();
    final headers = <String, dynamic>{};
    if (forManage) {
      final token = _manageToken(configMap);
      if (token.isNotEmpty) {
        headers['Authorization'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
      }
    }
    options.headers = headers;
    return Dio(options);
  }

  Future<String> host() async {
    final configMap = await _safeConfig();
    return _normalizeHost(configMap['host']?.toString() ?? '');
  }

  /// GET /api/manage/list
  Future<List> getFileList({
    int start = 0,
    int count = 50,
    String dir = '',
    bool recursive = false,
    String search = '',
    String fileType = 'image',
  }) async {
    try {
      final h = await host();
      if (h.isEmpty) return ['failed', '未配置 host'];
      final dio = await _dio();
      final response = await dio.get(
        '$h/api/manage/list',
        queryParameters: {
          'start': start,
          'count': count,
          if (dir.isNotEmpty) 'dir': dir,
          'recursive': recursive,
          if (search.isNotEmpty) 'search': search,
          if (fileType.isNotEmpty) 'fileType': fileType,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        return ['success', response.data];
      }
      flogErr(response, {'start': start, 'count': count, 'dir': dir}, 'CfimgbedManageAPI', 'getFileList');
      return ['failed', response.data];
    } catch (e) {
      flogErr(e, {'start': start, 'count': count, 'dir': dir}, 'CfimgbedManageAPI', 'getFileList');
      return [e.toString()];
    }
  }

  Future<List<String>> deleteFile(String path) async {
    try {
      final h = await host();
      if (h.isEmpty || path.isEmpty) return ['failed'];
      final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
      final dio = await _dio();
      final response = await dio.get('$h/api/manage/delete/$encodedPath');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['success'] == true) return ['success'];
        if (data is String && data.toLowerCase().contains('success')) return ['success'];
        if (data is Map && data['error'] == null && data['fileId'] != null) return ['success'];
      }
      flogErr(response, {'path': path}, 'CfimgbedManageAPI', 'deleteFile');
      return ['failed'];
    } catch (e) {
      flogErr(e, {'path': path}, 'CfimgbedManageAPI', 'deleteFile');
      return [e.toString()];
    }
  }

  Future<List<String>> uploadFile(String filename, String path) async {
    try {
      final configMap = await _safeConfig();
      final h = _normalizeHost(configMap['host']?.toString() ?? '');
      final authCode = (configMap['authCode'] ?? '').toString().trim();
      final uploadChannel = (configMap['uploadChannel'] ?? 'telegram').toString().trim();
      final uploadFolder = (configMap['uploadFolder'] ?? '').toString().trim();
      final channelName = (configMap['channelName'] ?? '').toString().trim();
      final apiToken = (configMap['apiToken'] ?? '').toString().trim();
      if (h.isEmpty) return ['failed'];

      final query = <String, dynamic>{
        'returnFormat': 'full',
        'uploadChannel': uploadChannel.isEmpty ? 'telegram' : uploadChannel,
        if (authCode.isNotEmpty) 'authCode': authCode,
        if (uploadFolder.isNotEmpty) 'uploadFolder': uploadFolder,
        if (channelName.isNotEmpty) 'channelName': channelName,
      };

      final options = setBaseOptions();
      options.headers = {
        'Content-Type': 'multipart/form-data',
        if (apiToken.isNotEmpty) 'Authorization': apiToken.startsWith('Bearer ') ? apiToken : 'Bearer $apiToken',
      };
      final dio = Dio(options);
      final response = await dio.post(
        '$h/upload',
        queryParameters: query,
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(path, filename: filename),
        }),
      );
      if (response.statusCode == 200 && response.data is List && (response.data as List).isNotEmpty) {
        return ['success'];
      }
      return ['failed'];
    } catch (e) {
      flogErr(e, {'filename': filename, 'path': path}, 'CfimgbedManageAPI', 'uploadFile');
      return [e.toString()];
    }
  }

  Future<List<String>> uploadNetworkFile(String fileLink) async {
    try {
      String filename = fileLink.substring(fileLink.lastIndexOf('/') + 1);
      filename = filename.substring(0, !filename.contains('?') ? filename.length : filename.indexOf('?'));
      if (filename.isEmpty) filename = 'network_file';
      final savePath = await getTemporaryDirectory().then((v) => v.path);
      final saveFilePath = '$savePath/$filename';
      final dio = Dio();
      final response = await dio.download(fileLink, saveFilePath);
      if (response.statusCode != 200) return ['failed'];
      return await uploadFile(filename, saveFilePath);
    } catch (e) {
      flogErr(e, {'fileLink': fileLink}, 'CfimgbedManageAPI', 'uploadNetworkFile');
      return ['failed'];
    }
  }

  Future uploadNetworkFileEntry(List fileList) async {
    int successCount = 0;
    int failCount = 0;
    for (String fileLink in fileList) {
      if (fileLink.isEmpty) continue;
      final uploadResult = await uploadNetworkFile(fileLink);
      if (uploadResult[0] == 'success') {
        successCount++;
      } else {
        failCount++;
      }
    }
    if (successCount == 0) return showToast('上传失败');
    if (failCount == 0) return showToast('上传成功');
    return showToast('成功$successCount,失败$failCount');
  }

  /// Build public URL for a file path/id.
  Future<String> buildFileUrl(String filePath) async {
    final configMap = await _safeConfig();
    final h = _normalizeHost(configMap['host']?.toString() ?? '');
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    final id = filePath.startsWith('/file/')
        ? filePath.substring('/file/'.length)
        : (filePath.startsWith('file/') ? filePath.substring(5) : filePath.replaceFirst(RegExp(r'^/'), ''));
    return '$h/file/$id';
  }

  String displayName(String filePath) => my_path.basename(filePath);
}
