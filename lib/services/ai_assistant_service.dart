// AI 助手服务
// 基于 OpenAI 兼容 API（DeepSeek / OpenAI / Kimi / Ollama 等）的 agent 服务。
//
// 提供一组工具（读日志、查文件、启停实例、发送命令等）供模型调用：
// - 只读工具（读日志/读文件/列表）直接执行，无需确认；
// - 敏感工具（执行命令、启停实例）必须等待用户通过 resolvePermission 授权，
//   用户拒绝时返回"用户拒绝了该操作"给模型。
// 每次对话为一次 agent 循环：消息 → 模型 → 工具调用 → 结果回填 → 直至模型给出最终回答。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/server_instance.dart';
import '../services/ai_settings.dart';
import '../services/http_ffi.dart';
import '../services/knowledge_service.dart';
import '../services/log_persistence.dart';
import '../state/app_state.dart';

/// 工具权限级别。
enum AiToolPermission {
  /// 只读，直接执行。
  read,

  /// 敏感操作，需要用户授权。
  elevated,
}

/// 对话过程中的事件类型。
enum AiEventKind {
  /// 用户消息（UI 自行构造）。
  user,

  /// 模型思考中（等待 API 响应）。
  thinking,

  /// 模型的文本回答。
  text,

  /// 模型请求调用工具。
  toolCall,

  /// 工具执行完成的结果。
  toolResult,

  /// 需要用户授权的敏感操作。
  permission,

  /// 正在压缩对话历史。
  compressing,

  /// 对话历史压缩完成。
  compressed,

  /// 发生错误。
  error,
}

/// 对话过程中的一条事件。
class AiEvent {
  final AiEventKind kind;
  final String? text;
  final String? toolName;
  final String? toolSummary;
  final Map<String, dynamic>? toolArgs;
  final String? error;

  const AiEvent({
    required this.kind,
    this.text,
    this.toolName,
    this.toolSummary,
    this.toolArgs,
    this.error,
  });

  const AiEvent.user(String message)
    : kind = AiEventKind.user,
      text = message,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = null;

  const AiEvent.thinking()
    : kind = AiEventKind.thinking,
      text = null,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = null;

  const AiEvent.text(String message)
    : kind = AiEventKind.text,
      text = message,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = null;

  const AiEvent.toolCall(String name, Map<String, dynamic> args, String summary)
    : kind = AiEventKind.toolCall,
      text = null,
      toolName = name,
      toolSummary = summary,
      toolArgs = args,
      error = null;

  const AiEvent.toolResult(String name, String summary)
    : kind = AiEventKind.toolResult,
      text = null,
      toolName = name,
      toolSummary = summary,
      toolArgs = null,
      error = null;

  const AiEvent.permission(
    String name,
    Map<String, dynamic> args,
    String summary,
  ) : kind = AiEventKind.permission,
      text = null,
      toolName = name,
      toolSummary = summary,
      toolArgs = args,
      error = null;

  const AiEvent.compressing()
    : kind = AiEventKind.compressing,
      text = null,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = null;

  const AiEvent.compressed(String summary)
    : kind = AiEventKind.compressed,
      text = summary,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = null;

  const AiEvent.error(String message)
    : kind = AiEventKind.error,
      text = null,
      toolName = null,
      toolSummary = null,
      toolArgs = null,
      error = message;
}

/// 一个可被模型调用的工具。
class AiTool {
  final String name;
  final String description;

  /// JSON Schema 形式的参数定义。
  final Map<String, dynamic> parameters;
  final AiToolPermission permission;

  /// 生成面向用户的中文描述（用于权限卡片与对话展示）。
  final String Function(Map<String, dynamic> args) describe;
  final Future<String> Function(AppState state, Map<String, dynamic> args)
  handler;

  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.permission,
    required this.describe,
    required this.handler,
  });
}

/// 一次 AI 对话会话。
///
/// 持有独立的对话历史与授权状态；同一应用可有多个会话
/// （导航栏 AI 页与实例详情页侧栏互不干扰）。
class AiConversation {
  AiConversation(this.service);

  final AiAssistantService service;

  /// 对话历史（OpenAI messages 格式）。
  final List<Map<String, dynamic>> _messages = [];

  /// 待用户授权的 completer；为 null 表示当前无待授权操作。
  Completer<bool>? _permissionCompleter;

  bool _running = false;
  bool _cancelled = false;

  /// 当前正在使用的模型（本轮对话开始时读取）。
  AiModelConfig? _model;

  /// 当前是否在运行一轮对话。
  bool get running => _running;

  /// 是否有待用户授权的敏感操作。
  bool get hasPendingPermission => _permissionCompleter != null;

  /// 清空对话历史。
  void resetConversation() {
    _messages.clear();
    _cancelled = false;
  }

  /// 停止当前对话（待授权的操作视为拒绝）。
  void cancel() {
    _cancelled = true;
    _permissionCompleter?.complete(false);
    _permissionCompleter = null;
  }

  /// 用户对敏感操作授权：true 允许，false 拒绝。
  void resolvePermission(bool allowed) {
    _permissionCompleter?.complete(allowed);
    _permissionCompleter = null;
  }

  /// 运行一轮对话：用户消息 → agent 循环 → 最终回答。
  ///
  /// [emit] 在每产生一个事件时回调（UI 刷新用）。
  /// 敏感工具调用会先发出 [AiEventKind.permission] 事件并挂起，
  /// 等待 [resolvePermission] 后才继续。
  Future<void> runTurn(
    AppState state,
    String userText, {
    required void Function(AiEvent event) emit,
  }) async {
    if (_running) return;
    _running = true;
    _cancelled = false;

    final model = await AiSettings.getActiveModel();
    if (model == null) {
      emit(const AiEvent.error('尚未添加 AI 模型，请先点击左上角添加模型'));
      _running = false;
      return;
    }
    _model = model;

    _messages.add({'role': 'user', 'content': userText});
    try {
      var iterations = 0;
      while (!_cancelled && iterations < 12) {
        iterations++;
        emit(const AiEvent.thinking());
        final message = await service._chatCompletion(_messages, model);
        if (message == null) {
          emit(const AiEvent.error('模型无响应（choices 为空）'));
          break;
        }
        // 保留完整 assistant 消息（含 tool_calls）作为上下文。
        _messages.add(message);

        final content = message['content'] as String?;
        if (content != null && content.trim().isNotEmpty) {
          emit(AiEvent.text(content));
        }

        final toolCalls = message['tool_calls'] as List?;
        if (toolCalls == null || toolCalls.isEmpty) break;

        for (final tc in toolCalls) {
          if (_cancelled) break;
          final fn =
              (tc as Map<String, dynamic>)['function'] as Map<String, dynamic>;
          final name = fn['name'] as String? ?? '?';
          final args = AiAssistantService.parseArgs(fn['arguments']);
          final tool = service.tools.where((t) => t.name == name).firstOrNull;

          if (tool == null) {
            _messages.add({
              'role': 'tool',
              'tool_call_id': tc['id'],
              'content': '未知工具: $name',
            });
            emit(AiEvent.toolResult(name, '未知工具，已忽略'));
            continue;
          }

          emit(AiEvent.toolCall(name, args, tool.describe(args)));

          String result;
          if (tool.permission == AiToolPermission.elevated) {
            _permissionCompleter = Completer<bool>();
            emit(AiEvent.permission(name, args, tool.describe(args)));
            final allowed = await _permissionCompleter!.future;
            _permissionCompleter = null;
            if (_cancelled || !allowed) {
              result = '用户拒绝了该操作: ${tool.describe(args)}';
            } else {
              result = await service._safeHandle(tool, state, args);
            }
          } else {
            result = await service._safeHandle(tool, state, args);
          }

          _messages.add({
            'role': 'tool',
            'tool_call_id': tc['id'],
            'content': result,
          });
          emit(AiEvent.toolResult(name, result));
        }
      }
      if (_cancelled) {
        emit(const AiEvent.text('已停止。'));
      } else {
        // 根据上下文窗口压缩过长的对话历史。
        await _compressIfNeeded(emit);
      }
    } catch (e) {
      emit(AiEvent.error(e.toString()));
    } finally {
      _running = false;
    }
  }

  /// 估算当前对话历史的 token 用量。
  int _estimateTokens() {
    var total = 0;
    for (final message in _messages) {
      final content = message['content'];
      if (content is String) {
        total += AiAssistantService.estimateTokens(content);
      }
    }
    return total;
  }

  /// 当历史估算用量超过上下文窗口的 60% 时，
  /// 把较早的对话交给 AI 压缩为摘要，替换为一条 system 摘要消息。
  Future<void> _compressIfNeeded(void Function(AiEvent event) emit) async {
    final model = _model;
    if (model == null || model.contextWindow <= 0) return;
    if (_messages.length < 8) return;
    if (_estimateTokens() < model.contextWindow * 0.6) return;

    const keepCount = 4;
    final toCompress = _messages.sublist(0, _messages.length - keepCount);
    final rest = _messages.sublist(_messages.length - keepCount);

    emit(const AiEvent.compressing());
    final summary = await service._summarizeHistory(toCompress, model);
    if (summary == null || summary.trim().isEmpty) return;

    _messages
      ..clear()
      ..add({
        'role': 'system',
        'content': '以下是此前对话的压缩摘要，请基于摘要继续帮助用户：\n$summary',
      })
      ..addAll(rest);
    emit(AiEvent.compressed(summary));
  }
}

/// AI 助手服务（单例）。
class AiAssistantService {
  static final AiAssistantService instance = AiAssistantService._();
  AiAssistantService._();

  /// 全部可用工具。
  final List<AiTool> tools = _buildTools();

  /// 创建新的独立会话。
  AiConversation createConversation() => AiConversation(this);

  Future<Map<String, dynamic>?> _chatCompletion(
    List<Map<String, dynamic>> messages,
    AiModelConfig model,
  ) async {
    final body = jsonEncode({
      'model': model.name,
      'messages': messages,
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          },
      ],
      'tool_choice': 'auto',
    });

    final res = await HttpFfiService.instance.post(
      _endpoint(model.baseUrl),
      headers: _headers(model.apiKey),
      body: body,
      timeout: const Duration(seconds: 120),
    );
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${_snippet(res.body)}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final message = Map<String, dynamic>.from(
      (choices.first as Map)['message'] as Map,
    );
    return message;
  }

  /// 调用模型把一段对话历史压缩为摘要。失败返回 null。
  Future<String?> _summarizeHistory(
    List<Map<String, dynamic>> history,
    AiModelConfig model,
  ) async {
    final dump = history
        .map((m) {
          final role = m['role']?.toString() ?? '?';
          final content = m['content']?.toString() ?? '';
          return '[$role] $content';
        })
        .join('\n');

    final body = jsonEncode({
      'model': model.name,
      'messages': [
        {
          'role': 'system',
          'content':
              '你是对话摘要压缩器。请将用户提供的对话记录压缩为简洁的中文摘要，'
              '保留关键事实：服务器实例名称、错误信息、已执行的操作与结论。'
              '不要添加原文没有的内容，只输出摘要本身。',
        },
        {'role': 'user', 'content': dump},
      ],
      'max_tokens': (model.contextWindow ~/ 8).clamp(256, 2048),
    });

    try {
      final res = await HttpFfiService.instance.post(
        _endpoint(model.baseUrl),
        headers: _headers(model.apiKey),
        body: body,
        timeout: const Duration(seconds: 120),
      );
      if (res.statusCode != 200) return null;
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final content = (choices.first as Map)['message']?['content']
          ?.toString()
          .trim();
      return (content == null || content.isEmpty) ? null : content;
    } catch (e) {
      debugPrint('History compression failed: $e');
      return null;
    }
  }

  /// 拼接 Chat Completions 端点地址。
  static String _endpoint(String baseUrl) {
    final url = baseUrl.trim();
    if (url.isEmpty) throw Exception('未配置 AI 服务地址');
    if (url.endsWith('/chat/completions')) return url;
    return '${url.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
  }

  static Map<String, String> _headers(String apiKey) => {
    'Content-Type': 'application/json',
    if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
  };

  /// 粗略估算文本 token 数：CJK 每字约 1 token，其余按 4 字符 1 token。
  static int estimateTokens(String text) {
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x20000 && rune <= 0x2A6DF)) {
        cjk++;
      } else {
        other++;
      }
    }
    return cjk + (other / 4).ceil();
  }

  Future<String> _safeHandle(AiTool tool, AppState state, Map args) async {
    try {
      final result = await tool.handler(state, Map<String, dynamic>.from(args));
      return _truncate(result, 8000);
    } catch (e) {
      return '工具执行失败: $e';
    }
  }

  static Map<String, dynamic> parseArgs(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
  }

  static String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n…(已截断 ${text.length - maxChars} 字符)';
  }

  // === 工具实现 ===

  /// 将相对路径解析到实例根目录内，越界时抛异常。
  ///
  /// 安全（L-1）：使用 `p.isWithin` 做目录边界判断，避免 `startsWith`
  /// 前缀匹配放行同前缀兄弟目录（如 `C:\inst` 放行 `C:\instance2\...`）。
  static String _resolvePath(ServerInstance instance, String relative) {
    final root = p.normalize(p.absolute(instance.rootPath));
    final target = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, target)) {
      throw Exception('路径越界，不允许访问根目录之外: $relative');
    }
    return target;
  }

  static List<AiTool> _buildTools() => [
    AiTool(
      name: 'list_instances',
      description: '列出所有服务器实例：ID、名称、运行状态与根目录路径',
      parameters: {'type': 'object', 'properties': {}, 'required': []},
      permission: AiToolPermission.read,
      describe: (_) => '查看实例列表',
      handler: (state, _) async {
        final lines = [
          for (final i in state.instances)
            '${i.id} | ${i.name} | ${i.status.label} | 根目录: ${i.rootPath}',
        ];
        if (lines.isEmpty) return '没有已创建的实例';
        return lines.join('\n');
      },
    ),
    AiTool(
      name: 'read_logs',
      description: '读取指定实例的服务器日志，默认最近 200 行（tail 参数可指定行数）',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
          'tail': {'type': 'integer', 'description': '读取最近 N 行，默认 200'},
        },
        'required': ['instance_id'],
      },
      permission: AiToolPermission.read,
      describe: (a) => '读取日志 · ${a['instance_id']} · 最近 ${a['tail'] ?? 200} 行',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final tail = (a['tail'] as num?)?.toInt() ?? 200;
        final log = await LogPersistence.readLogs(id, tail: tail);
        if (log == null) return '该实例没有日志文件';
        return '最近 $tail 行日志（共 ${log.length} 字符）:\n$log';
      },
    ),
    AiTool(
      name: 'search_logs',
      description: '在指定实例的日志中搜索匹配关键词或正则表达式的行（大小写不敏感）',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
          'pattern': {'type': 'string', 'description': '关键词或正则表达式'},
          'tail': {'type': 'integer', 'description': '在最近 N 行内搜索，默认 500'},
        },
        'required': ['instance_id', 'pattern'],
      },
      permission: AiToolPermission.read,
      describe: (a) => '搜索日志 · ${a['instance_id']} · 关键词 "${a['pattern']}"',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final pattern = a['pattern'].toString();
        final tail = (a['tail'] as num?)?.toInt() ?? 500;
        final log = await LogPersistence.readLogs(id, tail: tail);
        if (log == null) return '该实例没有日志文件';
        final regex = RegExp(pattern, caseSensitive: false);
        final matches = <String>[];
        var lineNo = 0;
        for (final line in log.split('\n')) {
          lineNo++;
          if (regex.hasMatch(line)) {
            matches.add('[$lineNo] $line');
            if (matches.length >= 60) break;
          }
        }
        if (matches.isEmpty) return '未找到匹配 "$pattern" 的行';
        return '匹配 ${matches.length} 行（可能截断）:\n${matches.join('\n')}';
      },
    ),
    AiTool(
      name: 'list_files',
      description: '列出实例根目录（或指定子目录）中的文件与文件夹',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
          'path': {'type': 'string', 'description': '相对根目录的子目录路径，默认 "" 表示根目录'},
        },
        'required': ['instance_id'],
      },
      permission: AiToolPermission.read,
      describe: (a) => '查看文件 · ${a['instance_id']} · 目录 "${a['path'] ?? ''}"',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final instance = state.instances.where((i) => i.id == id).firstOrNull;
        if (instance == null) return '实例不存在';
        final dir = Directory(
          _resolvePath(instance, a['path']?.toString() ?? ''),
        );
        if (!await dir.exists()) return '目录不存在: ${dir.path}';
        final entries = dir.listSync(recursive: false)
          ..sort((x, y) {
            final xd = x is Directory;
            final yd = y is Directory;
            if (xd != yd) return xd ? -1 : 1;
            return p
                .basename(x.path)
                .toLowerCase()
                .compareTo(p.basename(y.path).toLowerCase());
          });
        final lines = [
          for (final e in entries.take(200))
            '${e is Directory ? '[目录]' : '[文件]'} ${p.basename(e.path)}',
        ];
        if (lines.isEmpty) return '目录为空: ${dir.path}';
        if (entries.length > 200) {
          lines.add('…(共 ${entries.length} 项，仅显示前 200)');
        }
        lines.insert(0, '目录: ${dir.path}');
        return lines.join('\n');
      },
    ),
    AiTool(
      name: 'read_file',
      description: '读取实例目录内的文本文件内容（超过 60KB 只返回开头部分）',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
          'path': {
            'type': 'string',
            'description': '相对根目录的文件路径，例如 logs/latest.log',
          },
        },
        'required': ['instance_id', 'path'],
      },
      permission: AiToolPermission.read,
      describe: (a) => '读取文件 · ${a['instance_id']} · "${a['path']}"',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final instance = state.instances.where((i) => i.id == id).firstOrNull;
        if (instance == null) return '实例不存在';
        final file = File(_resolvePath(instance, a['path'].toString()));
        if (!await file.exists()) return '文件不存在: ${file.path}';
        final length = await file.length();
        if (length > 60 * 1024) {
          return '文件过大（$length 字节），仅读取开头部分:\n'
              '${await file.openRead(0, 60 * 1024).transform(utf8.decoder).join()}';
        }
        return await file.readAsString();
      },
    ),
    AiTool(
      name: 'search_knowledge',
      description:
          '在本地知识库（用户导入的文档）中检索与问题相关的内容，'
          '返回最相似的文本片段。当你认为答案可能来自知识库时使用。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '检索关键词或问题'},
          'top_k': {'type': 'integer', 'description': '返回片段数，默认 5'},
        },
        'required': ['query'],
      },
      permission: AiToolPermission.read,
      describe: (a) => '知识库检索 · "${a['query']}"',
      handler: (state, a) async {
        final model = await AiSettings.getActiveModel();
        if (model == null) return '尚未配置 AI 模型，无法获取 embedding';
        final query = a['query'].toString();
        final topK = (a['top_k'] as num?)?.toInt() ?? 5;
        final hits = await KnowledgeService.instance.search(
          model,
          query,
          topK: topK,
        );
        if (hits.isEmpty) return '知识库中没有相关内容（或知识库为空，可先在 AI 设置中导入文档）';
        final lines = <String>[];
        for (var i = 0; i < hits.length; i++) {
          final h = hits[i];
          lines.add(
            '[$i] <${h.title}> 相似度 ${(1 - h.distance).toStringAsFixed(3)}:\n${h.text}',
          );
        }
        return '知识库检索结果:\n${lines.join('\n\n')}';
      },
    ),
    AiTool(
      name: 'send_server_command',
      description: '向运行中的服务器控制台发送命令（如 op、whitelist、say、give 等）',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
          'command': {'type': 'string', 'description': '要执行的命令内容'},
        },
        'required': ['instance_id', 'command'],
      },
      permission: AiToolPermission.elevated,
      describe: (a) => '发送命令 · ${a['instance_id']} · "${a['command']}"',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final command = a['command'].toString();
        final instance = state.instances.where((i) => i.id == id).firstOrNull;
        if (instance == null) return '实例不存在';
        if (!instance.status.isActive) return '实例未运行，无法发送命令';
        state.sendCommand(id, command);
        return '命令已发送到 ${instance.name}: $command';
      },
    ),
    AiTool(
      name: 'start_instance',
      description: '启动指定服务器实例',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
        },
        'required': ['instance_id'],
      },
      permission: AiToolPermission.elevated,
      describe: (a) => '启动实例 · ${a['instance_id']}',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final instance = state.instances.where((i) => i.id == id).firstOrNull;
        if (instance == null) return '实例不存在';
        await state.startInstance(id);
        return '实例已启动: ${instance.name}';
      },
    ),
    AiTool(
      name: 'stop_instance',
      description: '优雅停止指定服务器实例（向控制台发送 stop）',
      parameters: {
        'type': 'object',
        'properties': {
          'instance_id': {'type': 'string', 'description': '实例 ID'},
        },
        'required': ['instance_id'],
      },
      permission: AiToolPermission.elevated,
      describe: (a) => '停止实例 · ${a['instance_id']}',
      handler: (state, a) async {
        final id = a['instance_id'].toString();
        final instance = state.instances.where((i) => i.id == id).firstOrNull;
        if (instance == null) return '实例不存在';
        await state.stopInstance(id);
        return '已向 ${instance.name} 发送停止命令';
      },
    ),
  ];
}
