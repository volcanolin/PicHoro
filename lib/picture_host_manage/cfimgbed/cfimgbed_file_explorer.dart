import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as flutter_services;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as my_path;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'package:horopic/picture_host_manage/manage_api/cfimgbed_manage_api.dart';
import 'package:horopic/utils/common_functions.dart';
import 'package:horopic/picture_host_manage/common/loading_state.dart' as loading_state;
import 'package:horopic/picture_host_manage/common/base_file_explorer_page.dart';

class CfimgbedFileExplorer extends BaseFileExplorer {
  const CfimgbedFileExplorer({super.key});

  @override
  CfimgbedFileExplorerState createState() => CfimgbedFileExplorerState();
}

class CfimgbedFileExplorerState extends BaseFileExplorerState<CfimgbedFileExplorer> {
  CfimgbedManageAPI get manageAPI => CfimgbedManageAPI();

  String currentDir = '';
  bool hasMore = true;
  int nextStart = 0;
  static const int pageSize = 50;

  @override
  Future<void> initializeData() async {
    await _getFileList(reset: true);
  }

  @override
  Future<void> refreshData() async {
    await _getFileList(reset: true);
  }

  Future<void> _getFileList({bool reset = false}) async {
    try {
      if (reset) {
        nextStart = 0;
        hasMore = true;
        allInfoList.clear();
        dirAllInfoList.clear();
        fileAllInfoList.clear();
      }
      if (!hasMore && !reset) return;

      final result = await manageAPI.getFileList(
        start: nextStart,
        count: pageSize,
        dir: currentDir,
        recursive: false,
        fileType: '',
      );
      if (result[0] != 'success') {
        if (reset) {
          state = loading_state.LoadState.error;
          if (mounted) setState(() {});
        }
        return;
      }

      final data = Map<String, dynamic>.from(result[1] as Map);
      final files = (data['files'] as List?) ?? [];
      final directories = (data['directories'] as List?) ?? [];

      if (reset) {
        dirAllInfoList.clear();
        fileAllInfoList.clear();
      }

      if (reset) {
        for (final d in directories) {
          final name = d.toString();
          dirAllInfoList.add({
            'isDir': true,
            'name': name,
            'path': name,
            'size': 0,
          });
        }
      }

      for (final f in files) {
        if (f is Map) {
          final name = (f['name'] ?? '').toString();
          final metadata = f['metadata'] is Map ? Map<String, dynamic>.from(f['metadata'] as Map) : <String, dynamic>{};
          final sizeRaw = metadata['FileSizeBytes'] ?? metadata['File-Size'] ?? metadata['FileSize'] ?? 0;
          fileAllInfoList.add({
            'isDir': false,
            'name': name,
            'path': name,
            'size': sizeRaw,
            'metadata': metadata,
          });
        } else {
          fileAllInfoList.add({
            'isDir': false,
            'name': f.toString(),
            'path': f.toString(),
            'size': 0,
            'metadata': <String, dynamic>{},
          });
        }
      }

      allInfoList
        ..clear()
        ..addAll(dirAllInfoList)
        ..addAll(fileAllInfoList);

      final returned = (data['returnedCount'] as num?)?.toInt() ?? files.length;
      nextStart += returned;
      final total = (data['totalCount'] as num?)?.toInt();
      if (total != null) {
        hasMore = nextStart < total;
      } else {
        hasMore = files.length >= pageSize;
      }

      selectedFilesBool = List.generate(allInfoList.length, (index) => false, growable: true);
      state = allInfoList.isEmpty ? loading_state.LoadState.empty : loading_state.LoadState.success;
    } catch (e) {
      flogErr(e, {}, 'CfimgbedFileExplorerState', '_getFileList');
      state = loading_state.LoadState.error;
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Future<String> getShareUrl(int index) async {
    final item = allInfoList[index];
    if (item['isDir'] == true) return '';
    return manageAPI.buildFileUrl(item['path']?.toString() ?? item['name']?.toString() ?? '');
  }

  @override
  String getFileName(int index) {
    final item = allInfoList[index];
    final name = item['name']?.toString() ?? '';
    if (item['isDir'] == true) {
      final cleaned = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
      final parts = cleaned.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? cleaned : parts.last;
    }
    return my_path.basename(name);
  }

  @override
  String getFileDate(int index) {
    final item = allInfoList[index];
    if (item['isDir'] == true) return '目录';
    final metadata = item['metadata'];
    String? ts;
    if (metadata is Map) {
      ts = (metadata['TimeStamp'] ?? metadata['timestamp'] ?? metadata['UploadTime'])?.toString();
    }
    if (ts == null || ts.isEmpty || ts == 'null') {
      return '';
    }
    final millis = int.tryParse(ts);
    if (millis != null) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(millis));
    }
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(ts));
    } catch (_) {
      return ts;
    }
  }

  @override
  String? getFileSizeForList(int index) {
    final item = allInfoList[index];
    if (item['isDir'] == true) return null;
    final size = int.tryParse((item['size'] ?? 0).toString().split('.').first) ?? 0;
    return size > 0 ? getFileSize(size) : null;
  }

  @override
  String getFormatedFileName(dynamic item) {
    if (item is Map && item['isDir'] == true) {
      final name = item['name']?.toString() ?? '';
      final parts = name.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? name : parts.last;
    }
    final name = item is Map ? (item['name']?.toString() ?? '') : item.toString();
    return my_path.basename(name);
  }

  @override
  String getPageTitle() => currentDir.isEmpty ? 'CloudFlare ImgBed' : currentDir;

  @override
  Future<void> deleteFiles(List<int> toDelete) async {
    toDelete = [...toDelete]..sort();
    for (int i = toDelete.length - 1; i >= 0; i--) {
      final idx = toDelete[i];
      final item = allInfoList[idx];
      if (item['isDir'] == true) {
        showToast('暂不支持删除目录');
        continue;
      }
      final path = item['path']?.toString() ?? item['name']?.toString() ?? '';
      final result = await manageAPI.deleteFile(path);
      if (result[0] != 'success') {
        throw Exception(result[0]);
      }
      // keep dir/file lists in sync
      if (idx < dirAllInfoList.length) {
        dirAllInfoList.removeAt(idx);
      } else {
        final fileIdx = idx - dirAllInfoList.length;
        if (fileIdx >= 0 && fileIdx < fileAllInfoList.length) {
          fileAllInfoList.removeAt(fileIdx);
        }
      }
      allInfoList.removeAt(idx);
      if (idx < selectedFilesBool.length) {
        selectedFilesBool.removeAt(idx);
      }
    }
    if (allInfoList.isEmpty) {
      state = loading_state.LoadState.empty;
    }
    if (mounted) setState(() {});
  }

  @override
  void navigateToDownloadManagement() {
    showToast('CloudFlare ImgBed 暂未接入批量下载管理');
  }

  Future<void> _openDir(Map item) async {
    var dir = item['path']?.toString() ?? item['name']?.toString() ?? '';
    dir = dir.replaceFirst(RegExp(r'^/'), '');
    if (dir.endsWith('/')) {
      dir = dir.substring(0, dir.length - 1);
    }
    currentDir = dir;
    await _getFileList(reset: true);
  }

  @override
  @override
  Future<void> onFileItemTap(int index) async {
    final item = allInfoList[index];
    if (item['isDir'] == true) {
      await _openDir(Map<String, dynamic>.from(item as Map));
      return;
    }
    final url = await getShareUrl(index);
    if (url.isEmpty) return;
    await flutter_services.Clipboard.setData(flutter_services.ClipboardData(text: url));
    showToast('已复制链接');
  }

  @override
  void showUploadOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                minLeadingWidth: 0,
                leading: const Icon(Icons.image_outlined, color: Colors.blue),
                title: const Text('上传照片'),
                onTap: () async {
                  Navigator.pop(context);
                  final List<AssetEntity>? pickedImage = await AssetPicker.pickAssets(
                    context,
                    pickerConfig: const AssetPickerConfig(
                      maxAssets: 100,
                      selectedAssets: [],
                      requestType: RequestType.image,
                    ),
                  );
                  if (pickedImage == null || pickedImage.isEmpty) {
                    return showToast('未选择照片');
                  }
                  int ok = 0;
                  for (final asset in pickedImage) {
                    final file = await asset.file;
                    if (file == null) continue;
                    final name = asset.title ?? file.path.split('/').last;
                    final result = await manageAPI.uploadFile(name, file.path);
                    if (result[0] == 'success') ok++;
                  }
                  showToast('上传完成 $ok/${pickedImage.length}');
                  await _getFileList(reset: true);
                },
              ),
              ListTile(
                minLeadingWidth: 0,
                leading: const Icon(Icons.link, color: Colors.blue),
                title: const Text('上传剪贴板内链接'),
                onTap: () async {
                  Navigator.pop(context);
                  final text = (await flutter_services.Clipboard.getData('text/plain'))?.text ?? '';
                  final links = text
                      .split(RegExp(r'\s+'))
                      .where((e) => e.startsWith('http://') || e.startsWith('https://'))
                      .toList();
                  if (links.isEmpty) {
                    return showToast('剪贴板无有效链接');
                  }
                  await manageAPI.uploadNetworkFileEntry(links);
                  await _getFileList(reset: true);
                },
              ),
              if (currentDir.isNotEmpty)
                ListTile(
                  minLeadingWidth: 0,
                  leading: const Icon(Icons.arrow_upward, color: Colors.blue),
                  title: const Text('返回上级目录'),
                  onTap: () async {
                    Navigator.pop(context);
                    final parts = currentDir.split('/').where((e) => e.isNotEmpty).toList();
                    if (parts.isEmpty) {
                      currentDir = '';
                    } else {
                      parts.removeLast();
                      currentDir = parts.join('/');
                    }
                    await _getFileList(reset: true);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Future<void> onDownloadButtonPressed() async {
    if (!selectedFilesBool.contains(true) || selectedFilesBool.isEmpty) {
      showToastWithContext(context, '没有选择文件');
      return;
    }
    final urls = <String>[];
    for (int i = 0; i < allInfoList.length; i++) {
      if (selectedFilesBool[i] == true && allInfoList[i]['isDir'] != true) {
        final url = await getShareUrl(i);
        if (url.isNotEmpty) urls.add(url);
      }
    }
    if (urls.isEmpty) {
      showToastWithContext(context, '没有可下载的文件');
      return;
    }
    await flutter_services.Clipboard.setData(flutter_services.ClipboardData(text: urls.join('\n')));
    showToast('已复制 ${urls.length} 个链接到剪贴板');
  }
}

