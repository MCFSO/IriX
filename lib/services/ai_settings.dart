// AI 助手设置 - 全局持久化
// 使用 SQLite (settings 表) 存储模型列表（可多个，含上下文窗口）与 MCP 配置。
// 旧版单模型配置（ai_base_url / ai_api_key / ai_model）会在首次读取时自动迁移。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';
import 'settings_repository.dart';

/// 一个 AI 模型配置。
class AiModelConfig {
  final String id;
  String name;
  String baseUrl;
  String apiKey;

  /// 上下文窗口大小（token 数），用于决定何时压缩对话历史。
  int contextWindow;

  /// 知识库 embedding 模型名（可选）；为空时知识库回退使用 [name]。
  String? embeddingModel;

  AiModelConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.contextWindow,
    this.embeddingModel,
  });

  /// 创建新模型（自动生成 id）。
  factory AiModelConfig.create({
    required String name,
    required String baseUrl,
    required String apiKey,
    required int contextWindow,
    String? embeddingModel,
  }) => AiModelConfig(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    contextWindow: contextWindow,
    embeddingModel: embeddingModel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'contextWindow': contextWindow,
    if (embeddingModel != null) 'embeddingModel': embeddingModel,
  };

  factory AiModelConfig.fromJson(Map<String, dynamic> json) => AiModelConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    apiKey: (json['apiKey'] as String?) ?? '',
    contextWindow: ((json['contextWindow'] as num?)?.toInt()) ?? 8192,
    embeddingModel: json['embeddingModel'] as String?,
  );
}

/// AI 助手设置服务。
class AiSettings {
  static const _keyModels = 'ai_models';
  static const _keyActiveModelId = 'ai_active_model';

  // 旧版单模型配置键（迁移用）。
  static const _legacyBaseUrl = 'ai_base_url';
  static const _legacyApiKey = 'ai_api_key';
  static const _legacyModel = 'ai_model';

  /// 默认上下文窗口（token）。
  static const int defaultContextWindow = 8192;

  // === 模型管理 ===

  /// 读取全部已保存模型；无新格式数据时尝试迁移旧版单模型配置。
  static Future<List<AiModelConfig>> getModels() async {
    try {
      final raw = await SettingsRepository.instance.getJson(
        _keyModels,
        label: 'AI models',
      );
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        return [
          for (final e in list)
            AiModelConfig.fromJson(e as Map<String, dynamic>),
        ];
      }
      return await _migrateLegacy();
    } catch (e) {
      debugPrint('Failed to get AI models: $e');
      return [];
    }
  }

  static Future<List<AiModelConfig>> _migrateLegacy() async {
    final baseUrl = await DatabaseManager.instance.getSetting(_legacyBaseUrl);
    final model = await DatabaseManager.instance.getSetting(_legacyModel);
    if (baseUrl == null ||
        baseUrl.trim().isEmpty ||
        model == null ||
        model.trim().isEmpty) {
      return [];
    }
    final apiKey =
        await DatabaseManager.instance.getSetting(_legacyApiKey) ?? '';
    final config = AiModelConfig.create(
      name: model.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey,
      contextWindow: defaultContextWindow,
    );
    await _saveModels([config]);
    await DatabaseManager.instance.setSetting(_keyActiveModelId, config.id);
    await DatabaseManager.instance.setSetting(_legacyBaseUrl, '');
    await DatabaseManager.instance.setSetting(_legacyModel, '');
    await DatabaseManager.instance.setSetting(_legacyApiKey, '');
    return [config];
  }

  static Future<void> _saveModels(List<AiModelConfig> models) =>
      SettingsRepository.instance.setJson(
        _keyModels,
        jsonEncode([for (final m in models) m.toJson()]),
        label: 'AI models',
      );

  /// 当前使用的模型；未指定时取第一个。
  static Future<AiModelConfig?> getActiveModel() async {
    final models = await getModels();
    if (models.isEmpty) return null;
    final activeId = await SettingsRepository.instance.getStringOrNull(
      _keyActiveModelId,
      label: 'active model',
    );
    for (final m in models) {
      if (m.id == activeId) return m;
    }
    return models.first;
  }

  /// 设置当前使用的模型。
  static Future<void> setActiveModel(String id) =>
      SettingsRepository.instance.setString(
        _keyActiveModelId,
        id,
        label: 'active model',
      );

  /// 添加新模型并设为当前使用。
  static Future<void> addModel(AiModelConfig model) async {
    final models = await getModels();
    models.add(model);
    await _saveModels(models);
    await setActiveModel(model.id);
  }

  /// 更新已保存的模型配置。
  static Future<void> updateModel(AiModelConfig model) async {
    final models = await getModels();
    final index = models.indexWhere((m) => m.id == model.id);
    if (index < 0) return;
    models[index] = model;
    await _saveModels(models);
  }

  /// 删除模型；删除当前使用时自动切换到剩余第一个。
  static Future<void> removeModel(String id) async {
    final models = (await getModels()).where((m) => m.id != id).toList();
    await _saveModels(models);
    final activeId = await SettingsRepository.instance.getStringOrNull(
      _keyActiveModelId,
      label: 'active model',
    );
    if (activeId == id) {
      await SettingsRepository.instance.setString(
        _keyActiveModelId,
        models.isEmpty ? '' : models.first.id,
        label: 'active model',
      );
    }
  }

  // === 本地 MCP 服务器 ===

  static const _keyMcpEnabled = 'ai_mcp_enabled';
  static const _keyMcpPort = 'ai_mcp_port';

  /// 默认 MCP 端口。
  static const int defaultMcpPort = 39273;

  /// 获取 MCP 服务器是否启用。
  static Future<bool> getMcpEnabled() => SettingsRepository.instance.getBoolInt(
        _keyMcpEnabled,
        defaultValue: false,
        label: 'MCP enabled',
      );

  /// 设置 MCP 服务器开关。
  static Future<void> setMcpEnabled(bool enabled) =>
      SettingsRepository.instance.setBoolInt(
        _keyMcpEnabled,
        enabled,
        label: 'MCP enabled',
      );

  /// 获取 MCP 端口，未设置时返回 [defaultMcpPort]。
  static Future<int> getMcpPort() => SettingsRepository.instance.getIntClamped(
        _keyMcpPort,
        defaultValue: defaultMcpPort,
        min: 1024,
        max: 65535,
        label: 'MCP port',
      );

  /// 设置 MCP 端口，自动 clamp 到 1024-65535。
  static Future<void> setMcpPort(int port) =>
      SettingsRepository.instance.setIntClamped(
        _keyMcpPort,
        port,
        min: 1024,
        max: 65535,
        label: 'MCP port',
      );
}
