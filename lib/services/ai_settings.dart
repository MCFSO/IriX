// AI 助手设置 - 全局持久化
// 使用 SQLite (settings 表) 存储 OpenAI 兼容 API 的连接配置

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';

/// AI 助手设置服务。
///
/// 持久化 OpenAI 兼容 API 的服务地址、密钥与模型名称，
/// 支持 DeepSeek / OpenAI / Kimi / 本地 Ollama 等兼容接口。
class AiSettings {
  static const _keyBaseUrl = 'ai_base_url';
  static const _keyApiKey = 'ai_api_key';
  static const _keyModel = 'ai_model';

  /// 默认服务地址。
  static const String defaultBaseUrl = 'https://api.openai.com/v1';

  /// 默认模型名称。
  static const String defaultModel = 'gpt-4o-mini';

  /// 获取服务地址，未设置时返回 [defaultBaseUrl]。
  static Future<String> getBaseUrl() async {
    try {
      return await DatabaseManager.instance.getSetting(_keyBaseUrl) ??
          defaultBaseUrl;
    } catch (e) {
      debugPrint('Failed to get AI base url: $e');
      return defaultBaseUrl;
    }
  }

  /// 设置服务地址（空值清除）。
  static Future<void> setBaseUrl(String value) async {
    try {
      await DatabaseManager.instance.setSetting(_keyBaseUrl, value.trim());
    } catch (e) {
      debugPrint('Failed to set AI base url: $e');
    }
  }

  /// 获取 API 密钥（可能为空）。
  static Future<String> getApiKey() async {
    try {
      return (await DatabaseManager.instance.getSetting(_keyApiKey)) ?? '';
    } catch (e) {
      debugPrint('Failed to get AI api key: $e');
      return '';
    }
  }

  /// 设置 API 密钥（空值清除）。
  static Future<void> setApiKey(String value) async {
    try {
      await DatabaseManager.instance.setSetting(_keyApiKey, value.trim());
    } catch (e) {
      debugPrint('Failed to set AI api key: $e');
    }
  }

  /// 获取模型名称，未设置时返回 [defaultModel]。
  static Future<String> getModel() async {
    try {
      return await DatabaseManager.instance.getSetting(_keyModel) ??
          defaultModel;
    } catch (e) {
      debugPrint('Failed to get AI model: $e');
      return defaultModel;
    }
  }

  /// 设置模型名称（空值清除）。
  static Future<void> setModel(String value) async {
    try {
      await DatabaseManager.instance.setSetting(_keyModel, value.trim());
    } catch (e) {
      debugPrint('Failed to set AI model: $e');
    }
  }
}
