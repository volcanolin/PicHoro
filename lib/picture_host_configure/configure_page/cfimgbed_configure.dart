import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:horopic/widgets/net_loading_dialog.dart';
import 'package:horopic/utils/common_functions.dart';
import 'package:horopic/utils/global.dart';
import 'package:horopic/utils/event_bus_utils.dart';
import 'package:horopic/picture_host_manage/manage_api/cfimgbed_manage_api.dart';
import 'package:horopic/widgets/configure_widgets.dart';

class CfimgbedConfig extends StatefulWidget {
  const CfimgbedConfig({super.key});

  @override
  CfimgbedConfigState createState() => CfimgbedConfigState();
}

class CfimgbedConfigState extends State<CfimgbedConfig> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _authCodeController = TextEditingController();
  final _apiTokenController = TextEditingController();
  final _uploadFolderController = TextEditingController();
  final _channelNameController = TextEditingController();
  String _uploadChannel = 'telegram';
  final CfimgbedManageAPI _manageAPI = CfimgbedManageAPI();

  static const List<String> _channels = [
    'telegram',
    'cfr2',
    's3',
    'discord',
    'huggingface',
    'webdav',
  ];

  @override
  void initState() {
    super.initState();
    _initConfig();
  }

  Future<void> _initConfig() async {
    try {
      final configMap = await _manageAPI.getConfigMap();
      _hostController.text = configMap['host']?.toString() ?? '';
      _authCodeController.text = configMap['authCode']?.toString() ?? '';
      _apiTokenController.text = configMap['apiToken']?.toString() ?? '';
      _uploadFolderController.text = configMap['uploadFolder']?.toString() ?? '';
      _channelNameController.text = configMap['channelName']?.toString() ?? '';
      final channel = configMap['uploadChannel']?.toString() ?? 'telegram';
      _uploadChannel = _channels.contains(channel) ? channel : 'telegram';
      if (mounted) setState(() {});
    } catch (e) {
      flogErr(e, {}, 'CfimgbedConfigState', '_initConfig');
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _authCodeController.dispose();
    _apiTokenController.dispose();
    _uploadFolderController.dispose();
    _channelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ConfigureWidgets.buildConfigAppBar(title: 'CloudFlare ImgBed 配置', context: context),
      body: Form(
        key: _formKey,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            ConfigureWidgets.buildSettingCard(
              title: '基本配置',
              children: [
                ConfigureWidgets.buildFormField(
                  controller: _hostController,
                  labelText: '站点地址',
                  hintText: 'https://your.domain.com',
                  prefixIcon: Icons.language,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入站点地址';
                    }
                    return null;
                  },
                ),
                ConfigureWidgets.buildFormField(
                  controller: _authCodeController,
                  labelText: '上传认证码 authCode',
                  hintText: '用于上传的 authCode',
                  prefixIcon: Icons.vpn_key,
                ),
                ConfigureWidgets.buildFormField(
                  controller: _apiTokenController,
                  labelText: 'API Token（可选）',
                  hintText: '管理列表/删除建议填写，需 list+delete 权限',
                  prefixIcon: Icons.security,
                ),
              ],
            ),
            ConfigureWidgets.buildSettingCard(
              title: '上传选项',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('上传渠道 uploadChannel'),
                  subtitle: Text(_uploadChannel),
                  trailing: DropdownButton<String>(
                    value: _uploadChannel,
                    underline: const SizedBox.shrink(),
                    items: _channels
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _uploadChannel = v);
                    },
                  ),
                ),
                ConfigureWidgets.buildFormField(
                  controller: _channelNameController,
                  labelText: '渠道名称 channelName（可选）',
                  hintText: '多渠道时指定名称',
                  prefixIcon: Icons.label_outline,
                ),
                ConfigureWidgets.buildFormField(
                  controller: _uploadFolderController,
                  labelText: '上传目录（可选）',
                  hintText: '例如 img/phone',
                  prefixIcon: Icons.folder_open,
                ),
              ],
            ),
            ConfigureWidgets.buildSettingCard(
              title: '操作',
              children: [
                ConfigureWidgets.buildSettingItem(
                  context: context,
                  title: '保存设置',
                  icon: Icons.save,
                  onTap: () {
                    if (_formKey.currentState!.validate()) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) {
                          return NetLoadingDialog(
                            outsideDismiss: false,
                            loading: true,
                            loadingText: '配置中...',
                            requestCallBack: _saveConfig(),
                          );
                        },
                      );
                    }
                  },
                ),
                ConfigureWidgets.buildDivider(),
                ConfigureWidgets.buildSettingItem(
                  context: context,
                  title: '检查当前配置',
                  icon: Icons.check_circle,
                  onTap: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) {
                        return NetLoadingDialog(
                          outsideDismiss: false,
                          loading: true,
                          loadingText: '检查中...',
                          requestCallBack: _checkConfig(),
                        );
                      },
                    );
                  },
                ),
                ConfigureWidgets.buildDivider(),
                ConfigureWidgets.buildSettingItem(
                  context: context,
                  title: '设为默认图床',
                  icon: Icons.favorite,
                  onTap: _setdefault,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Text(
                '说明：\n'
                '1. 上传优先使用 authCode。\n'
                '2. 仓库列表/删除接口通常需要管理员 API Token（list/delete 权限）。\n'
                '3. 若仅配置 authCode，上传可用，管理页可能失败。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future _saveConfig() async {
    try {
      final model = CfimgbedConfigModel(
        _hostController.text.trim(),
        _authCodeController.text.trim(),
        _apiTokenController.text.trim(),
        _uploadChannel,
        _uploadFolderController.text.trim(),
        _channelNameController.text.trim(),
      );
      final file = await _manageAPI.localFile();
      await file.writeAsString(jsonEncode(model));
      showToast('保存成功');
    } catch (e) {
      flogErr(e, {}, 'CfimgbedConfigState', '_saveConfig');
      if (context.mounted) {
        return showCupertinoAlertDialog(context: context, title: '错误', content: e.toString());
      }
    }
  }

  Future _checkConfig() async {
    try {
      final configMap = await _manageAPI.getConfigMap();
      if (configMap.isEmpty || (configMap['host'] ?? '').toString().isEmpty) {
        if (context.mounted) {
          return showCupertinoAlertDialog(context: context, title: '检查失败!', content: '请先配置站点地址.');
        }
        return;
      }

      String host = configMap['host'].toString().trim();
      if (host.endsWith('/')) host = host.substring(0, host.length - 1);
      if (!host.startsWith('http')) host = 'https://$host';

      final authCode = (configMap['authCode'] ?? '').toString().trim();
      final apiToken = (configMap['apiToken'] ?? '').toString().trim();

      // Probe manage list if token exists; otherwise just check host reachable-ish via OPTIONS/upload unauthorized
      final options = setBaseOptions();
      if (apiToken.isNotEmpty) {
        options.headers = {
          'Authorization': apiToken.startsWith('Bearer ') ? apiToken : 'Bearer $apiToken',
        };
        final dio = Dio(options);
        final response = await dio.get('$host/api/manage/list', queryParameters: {'count': 1});
        if (response.statusCode == 200) {
          if (context.mounted) {
            return showCupertinoAlertDialog(
              context: context,
              title: '通知',
              content: '管理接口检测通过\nhost: $host\nuploadChannel: ${configMap['uploadChannel'] ?? 'telegram'}',
            );
          }
          return;
        }
      }

      // Upload auth probe: empty POST should not 404
      final dio2 = Dio(setBaseOptions());
      try {
        final probe = await dio2.post(
          '$host/upload',
          queryParameters: {
            if (authCode.isNotEmpty) 'authCode': authCode,
          },
        );
        // any non-404 means host path exists
        if (context.mounted) {
          return showCupertinoAlertDialog(
            context: context,
            title: '通知',
            content:
                '站点可达\nhost: $host\nauthCode: ${authCode.isEmpty ? "(空)" : "已填写"}\napiToken: ${apiToken.isEmpty ? "(空，管理功能可能不可用)" : "已填写"}\n探测状态码: ${probe.statusCode}',
          );
        }
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 401 || code == 400 || code == 403) {
          if (context.mounted) {
            return showCupertinoAlertDialog(
              context: context,
              title: '通知',
              content:
                  '上传端点可达（鉴权响应 $code）\nhost: $host\nauthCode: ${authCode.isEmpty ? "(空)" : "已填写"}\napiToken: ${apiToken.isEmpty ? "(空，管理功能可能不可用)" : "已填写"}',
            );
          }
          return;
        }
        rethrow;
      }
    } catch (e) {
      flogErr(e, {}, 'CfimgbedConfigState', '_checkConfig');
      if (context.mounted) {
        return showCupertinoAlertDialog(context: context, title: '检查失败!', content: e.toString());
      }
    }
  }

  void _setdefault() {
    Global.setPShost('cfimgbed');
    Global.setShowedPBhost('cfimgbed');
    eventBus.fire(AlbumRefreshEvent(albumKeepAlive: false));
    eventBus.fire(HomePhotoRefreshEvent(homePhotoKeepAlive: false));
    showToast('已设置 CloudFlare ImgBed 为默认图床');
  }
}

class CfimgbedConfigModel {
  final String host;
  final String authCode;
  final String apiToken;
  final String uploadChannel;
  final String uploadFolder;
  final String channelName;

  CfimgbedConfigModel(
    this.host,
    this.authCode,
    this.apiToken,
    this.uploadChannel,
    this.uploadFolder,
    this.channelName,
  );

  Map<String, dynamic> toJson() => {
        'host': host,
        'authCode': authCode,
        'apiToken': apiToken,
        'uploadChannel': uploadChannel,
        'uploadFolder': uploadFolder,
        'channelName': channelName,
      };

  static List keysList = [
    'remarkName',
    'host',
    'authCode',
    'apiToken',
    'uploadChannel',
    'uploadFolder',
    'channelName',
  ];
}
