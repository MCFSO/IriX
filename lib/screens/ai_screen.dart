// AI 助手页面与可复用聊天面板
//
// 设计要点：
// - 直接展示聊天框，不设置任何前置拦截页；
// - 未添加模型时在聊天区/输入栏直接提示「添加模型」；
// - 当前模型信息显示在面板左上角，点击可管理模型；
// - 添加模型时可指定上下文窗口，对话按上下文窗口自动压缩历史；
// - 敏感工具（执行命令、启停实例）弹出权限申请卡片，等待用户允许/拒绝。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/ai_assistant_service.dart';
import '../services/ai_settings.dart';
import '../services/knowledge_service.dart';
import '../services/log_parser.dart';
import '../services/mcp_server.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

/// 一次 AI 聊天的 UI 状态（事件列表 + 会话 + 当前模型）。
class AiChatController extends ChangeNotifier {
  AiChatController({required this.conversation});

  final AiConversation conversation;

  /// 展示用事件列表。
  final List<AiEvent> events = [];

  /// 当前使用的模型（未添加时为 null）。
  AiModelConfig? activeModel;

  /// 重新读取当前模型并通知 UI。
  Future<void> refreshModel() async {
    final model = await AiSettings.getActiveModel();
    if (model?.id != activeModel?.id ||
        model?.contextWindow != activeModel?.contextWindow) {
      activeModel = model;
      notifyListeners();
    }
  }

  void _onEvent(AiEvent event) {
    events.add(event);
    notifyListeners();
  }

  /// 发送一条用户消息并运行一轮 agent 循环。
  ///
  /// [displayText] 非空时，聊天气泡仅展示该摘要，而完整内容仍发给 AI。
  Future<void> send(AppState state, String text, {String? displayText}) async {
    if (conversation.running) return;
    _onEvent(AiEvent.user(displayText ?? text));
    await conversation.runTurn(state, text, emit: _onEvent);
  }

  /// 清空对话。
  void reset() {
    conversation.resetConversation();
    events.clear();
    notifyListeners();
  }
}

/// AI 聊天面板（无 Scaffold，可嵌入任意页面）。
///
/// [controller] 由外部持有以保持对话状态；[onClose] 非空时在面板
/// 顶部显示关闭按钮（用于侧栏场景）；[rootPath] 为实例根目录，
/// 非空时输入框上方显示「看日志」按钮，可从实例 logs/ 文件夹挑选日志。
class AiChatPanel extends StatefulWidget {
  final AiChatController controller;
  final VoidCallback? onClose;

  /// 实例根目录（用于读取实例 logs/ 文件夹中的日志）。
  final String? rootPath;

  /// 实例名称（发送日志给 AI 时附带）。
  final String? instanceName;

  const AiChatPanel({
    super.key,
    required this.controller,
    this.onClose,
    this.rootPath,
    this.instanceName,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.refreshModel();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (widget.controller.activeModel == null) {
      // 未添加模型时直接引导添加。
      await _openModels();
      return;
    }
    _input.clear();
    _scrollToBottom();
    await widget.controller.send(context.read<AppState>(), text);
  }

  Future<void> _openModels() async {
    await showAppDialog<void>(context, (_) => const _ModelsDialog());
    await widget.controller.refreshModel();
  }

  /// 从实例 logs/ 文件夹选择日志文件，解析后发送给 AI。
  Future<void> _pickServerLog() async {
    final rootPath = widget.rootPath;
    if (rootPath == null) return;
    final path = await showAppDialog<String>(
      context,
      (_) => _ServerLogPickerDialog(rootPath: rootPath),
    );
    if (path == null || !mounted) return;
    await _analyzeAndSendLog(path, source: '实例 logs/ 文件夹');
  }

  /// 通过系统文件选择器挑选 .log / .log.gz 文件，解析后发送给 AI。
  Future<void> _pickExternalLog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['log', 'gz'],
      withData: false,
    );
    final path = result?.files.first.path;
    if (path == null || !mounted) return;
    await _analyzeAndSendLog(path, source: '本地文件');
  }

  /// 解析日志文件并将格式化内容发送给 AI。
  Future<void> _analyzeAndSendLog(String path, {required String source}) async {
    final controller = widget.controller;
    if (controller.conversation.running) return;
    if (controller.activeModel == null) {
      await _openModels();
      return;
    }

    try {
      final parsed = await parseServerLog(path);
      if (!mounted) return;
      final message = buildLogAiMessage(
        parsed,
        instanceName: widget.instanceName,
        source: source,
      );
      final display =
          '已发送日志「${parsed.fileName}」'
          '（${parsed.compressed ? 'gzip 已解压，' : ''}${parsed.lineCount} 行'
          '${parsed.truncated ? '，已保留末尾' : ''}）供 AI 分析';
      _scrollToBottom();
      await controller.send(
        context.read<AppState>(),
        message,
        displayText: display,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('日志解析失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final conversation = controller.conversation;
        return Column(
          children: [
            _buildHeader(conversation),
            Expanded(child: _buildChat(conversation)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(AiConversation conversation) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          // 左上角：当前模型信息
          Expanded(child: _buildModelChip(theme)),
          if (conversation.running)
            IconButton(
              icon: const Icon(Icons.stop, size: 20),
              tooltip: '停止',
              visualDensity: VisualDensity.compact,
              onPressed: conversation.cancel,
            ),
          if (!conversation.running && widget.controller.events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '清空对话',
              visualDensity: VisualDensity.compact,
              onPressed: widget.controller.reset,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '模型与 MCP 设置',
            visualDensity: VisualDensity.compact,
            onPressed: _openModels,
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: '关闭 AI 面板',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  /// 左上角模型信息（名称 + 上下文窗口）。
  Widget _buildModelChip(ThemeData theme) {
    final model = widget.controller.activeModel;
    final InkWell clickable = InkWell(
      onTap: _openModels,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              model == null ? Icons.add_circle_outline : Icons.smart_toy,
              size: 18,
              color: model == null
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                model == null
                    ? '添加模型'
                    : '${model.name} · ${_contextLabel(model.contextWindow)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: model == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
    return clickable;
  }

  static String _contextLabel(int tokens) {
    if (tokens >= 1024 && tokens % 1024 == 0) {
      return '${tokens ~/ 1024}K';
    }
    return '$tokens';
  }

  Widget _buildChat(AiConversation conversation) {
    final controller = widget.controller;
    return Column(
      children: [
        Expanded(
          child: controller.events.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: controller.events.length,
                  itemBuilder: (context, index) {
                    final event = controller.events[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildEvent(event),
                    );
                  },
                ),
        ),
        _buildInputBar(conversation),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final hasModel = widget.controller.activeModel != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasModel ? Icons.smart_toy_outlined : Icons.add_circle_outline,
              size: 56,
              color: hasModel
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              hasModel ? '开始和 AI 对话吧' : '请先添加模型',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasModel
                  ? '可以让 AI 查看日志、分析报错、管理文件'
                  : '配置 OpenAI 兼容 API 模型（DeepSeek / OpenAI / Ollama 等）后即可使用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (!hasModel) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openModels,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加模型'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEvent(AiEvent event) {
    final theme = Theme.of(context);
    switch (event.kind) {
      case AiEventKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              event.text ?? '',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
        );
      case AiEventKind.text:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildMarkdown(event.text ?? ''),
          ),
        );
      case AiEventKind.thinking:
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 思考中…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      case AiEventKind.toolCall:
        return _buildToolChip(
          icon: Icons.auto_awesome,
          color: theme.colorScheme.primary,
          text: event.toolSummary ?? event.toolName ?? '',
        );
      case AiEventKind.toolResult:
        final summary = event.toolSummary ?? '';
        final isDenied = summary.contains('拒绝了') || summary.startsWith('用户');
        final isError =
            summary.startsWith('工具执行失败') || summary.startsWith('未知工具');
        return _buildToolChip(
          icon: isDenied
              ? Icons.block
              : isError
              ? Icons.error_outline
              : Icons.check_circle_outline,
          color: isDenied || isError
              ? theme.colorScheme.error
              : Colors.green.shade400,
          text: summary.length > 120
              ? '${summary.substring(0, 120)}…'
              : summary,
        );
      case AiEventKind.permission:
        return _buildPermissionCard(event);
      case AiEventKind.compressing:
        return _buildToolChip(
          icon: Icons.compress,
          color: theme.colorScheme.tertiary,
          text: '对话历史较长，正在压缩…',
        );
      case AiEventKind.compressed:
        final summary = event.text ?? '';
        return _buildToolChip(
          icon: Icons.compress,
          color: theme.colorScheme.tertiary,
          text:
              '已压缩对话历史：${summary.length > 120 ? '${summary.substring(0, 120)}…' : summary}',
        );
      case AiEventKind.error:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.error ?? '',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
    }
  }

  /// 渲染 AI 回复中的 markdown 内容（适配全局暗色主题）。
  Widget _buildMarkdown(String text) {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    // 代码块使用深色底 + 等宽字体，与日志面板风格一致。
    final codeColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.9,
    );
    final styleSheet = base.copyWith(
      codeblockDecoration: BoxDecoration(
        color: codeColor,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      code: base.code?.copyWith(
        backgroundColor: codeColor,
        fontFamily: 'monospace',
        fontSize: 12.5,
      ) ??
        TextStyle(
          backgroundColor: codeColor,
          fontFamily: 'monospace',
          fontSize: 12.5,
        ),
      p: base.p?.copyWith(height: 1.5) ?? const TextStyle(height: 1.5),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      tableHead: base.tableHead?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.4),
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
    return MarkdownBody(
      data: text,
      styleSheet: styleSheet,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        // 尝试用系统浏览器打开。
        if (Uri.tryParse(href) case final uri?) {
          _openExternal(uri);
        }
      },
    );
  }

  /// 打开外部链接（系统浏览器）。
  Future<void> _openExternal(Uri uri) async {
    try {
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        await Process.start(
          Platform.isWindows ? 'cmd' : 'xdg-open',
          Platform.isWindows ? ['/c', 'start', uri.toString()] : [uri.toString()],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (e) {
      debugPrint('打开链接失败: $e');
    }
  }

  Widget _buildToolChip({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(AiEvent event) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                'AI 申请执行敏感操作',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.toolSummary ?? '', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    widget.controller.conversation.resolvePermission(false),
                child: const Text('拒绝'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    widget.controller.conversation.resolvePermission(true),
                child: const Text('允许'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(AiConversation conversation) {
    final theme = Theme.of(context);
    final hasModel = widget.controller.activeModel != null;
    final busy = conversation.running;
    final hasLogsShortcut = widget.rootPath != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上排：看日志按钮
          if (hasLogsShortcut) ...[
            Row(
              children: [
                TextButton.icon(
                  onPressed: busy ? null : _pickServerLog,
                  icon: const Icon(Icons.manage_search, size: 16),
                  label: const Text('看日志'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '从实例 logs/ 文件夹挑选日志，解析后发送给 AI 分析',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          // 下排：文件选择（左）+ 输入框 + 发送
          Row(
            children: [
              IconButton(
                tooltip: '选择日志文件（.log / .log.gz），解析后发送给 AI',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : _pickExternalLog,
                icon: const Icon(Icons.attach_file, size: 18),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !conversation.running,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: hasModel ? '向 AI 提问…' : '请先添加模型再开始对话',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: hasModel ? '发送' : '添加模型',
                onPressed: conversation.running
                    ? null
                    : hasModel
                    ? _send
                    : _openModels,
                icon: Icon(hasModel ? Icons.send : Icons.add, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 导航栏 AI 分区页：直接显示聊天框。
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  late final AiChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AiChatController(
      conversation: AiAssistantService.instance.createConversation(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手')),
      body: AiChatPanel(controller: _controller),
    );
  }
}

/// 模型管理与 MCP 设置对话框。
class _ModelsDialog extends StatefulWidget {
  const _ModelsDialog();

  @override
  State<_ModelsDialog> createState() => _ModelsDialogState();
}

class _ModelsDialogState extends State<_ModelsDialog> {
  List<AiModelConfig> _models = [];
  String? _activeId;

  bool _mcpEnabled = false;
  final _mcpPortController = TextEditingController();

  /// 知识库文档列表与加载状态。
  List<KnowledgeDocument> _knowledgeDocs = [];
  bool _knowledgeLoading = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadKnowledge();
  }

  @override
  void dispose() {
    _mcpPortController.dispose();
    super.dispose();
  }

  Future<void> _loadKnowledge() async {
    setState(() => _knowledgeLoading = true);
    try {
      final docs = await KnowledgeService.instance.listDocuments();
      if (!mounted) return;
      setState(() => _knowledgeDocs = docs);
    } catch (e) {
      debugPrint('Failed to load knowledge docs: $e');
      if (mounted) {
        setState(() => _knowledgeDocs = []);
      }
    } finally {
      if (mounted) setState(() => _knowledgeLoading = false);
    }
  }

  Future<void> _importKnowledge() async {
    if (_importing) return;
    final model = await AiSettings.getActiveModel();
    if (model == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先添加 AI 模型，知识库导入需要调用 Embedding 接口')),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
      withData: false,
    );
    final path = result?.files.first.path;
    if (path == null) return;

    String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取文件失败: $e')));
      }
      return;
    }

    setState(() => _importing = true);
    try {
      await KnowledgeService.instance.importDocument(
        model,
        title: path.split(Platform.pathSeparator).last,
        content: content,
      );
      await _loadKnowledge();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('知识库导入完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _deleteKnowledge(KnowledgeDocument doc) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除文档'),
        content: Text('确定从知识库删除 "${doc.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await KnowledgeService.instance.deleteDocument(doc.id);
      await _loadKnowledge();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  Future<void> _load() async {
    final models = await AiSettings.getModels();
    final active = await AiSettings.getActiveModel();
    final mcpEnabled = await AiSettings.getMcpEnabled();
    final mcpPort = await AiSettings.getMcpPort();
    if (!mounted) return;
    setState(() {
      _models = models;
      _activeId = active?.id;
      _mcpEnabled = mcpEnabled;
      _mcpPortController.text = '$mcpPort';
    });
  }

  Future<void> _addModel() async {
    final model = await showAppDialog<AiModelConfig>(
      context,
      (_) => const _ModelEditDialog(),
    );
    if (model == null) return;
    await AiSettings.addModel(model);
    await _load();
  }

  Future<void> _editModel(AiModelConfig model) async {
    final updated = await showAppDialog<AiModelConfig>(
      context,
      (_) => _ModelEditDialog(model: model),
    );
    if (updated == null) return;
    await AiSettings.updateModel(updated);
    await _load();
  }

  Future<void> _deleteModel(AiModelConfig model) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除模型 "${model.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AiSettings.removeModel(model.id);
    await _load();
  }

  Future<void> _saveMcp() async {
    await AiSettings.setMcpEnabled(_mcpEnabled);
    await AiSettings.setMcpPort(
      int.tryParse(_mcpPortController.text.trim()) ?? AiSettings.defaultMcpPort,
    );
    try {
      if (_mcpEnabled) {
        await McpServer.instance.start(
          int.tryParse(_mcpPortController.text.trim()) ??
              AiSettings.defaultMcpPort,
        );
      } else {
        await McpServer.instance.stop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('MCP 服务器启动失败: $e')));
      }
    }
  }

  void _copyEndpoint() {
    final endpoint = McpServer.instance.endpoint;
    Clipboard.setData(ClipboardData(text: endpoint));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $endpoint')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // === 模型管理 ===
              Row(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '模型',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _addModel,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加模型'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_models.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '还没有模型，点击右上角「添加模型」',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _models.length,
                    itemBuilder: (context, index) {
                      final model = _models[index];
                      final isActive = model.id == _activeId;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isActive
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        title: Text(
                          model.name,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${model.baseUrl}\n上下文窗口: ${model.contextWindow} tokens',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _editModel(model),
                            ),
                            IconButton(
                              tooltip: '删除',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: theme.colorScheme.error,
                              ),
                              onPressed: () => _deleteModel(model),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await AiSettings.setActiveModel(model.id);
                          await _load();
                        },
                      );
                    },
                  ),
                ),
              const Divider(height: 24),
              // === 知识库（RAG）===
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '知识库',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _importing ? null : _importKnowledge,
                    icon: _importing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file, size: 18),
                    label: Text(_importing ? '导入中…' : '导入文档'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_knowledgeLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_knowledgeDocs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '知识库为空。导入 .txt/.md 文档后，AI 对话时可检索知识库内容。\n'
                    '（需在模型设置中配置 Embedding 模型，或留空使用同名模型）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _knowledgeDocs.length,
                    itemBuilder: (context, index) {
                      final doc = _knowledgeDocs[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          doc.title,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${doc.chunkCount} 个分块 · ${doc.createdAt}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '删除',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () => _deleteKnowledge(doc),
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 24),
              // === MCP 服务器 ===
              Row(
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '本地 MCP 服务器',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _mcpEnabled,
                    onChanged: (v) {
                      setState(() => _mcpEnabled = v);
                      _saveMcp();
                    },
                  ),
                ],
              ),
              if (_mcpEnabled) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _mcpPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _saveMcp(),
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: McpServer.instance.running
                            ? Colors.green
                            : theme.colorScheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        McpServer.instance.running
                            ? '运行中 ${McpServer.instance.endpoint}'
                            : '未运行',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (McpServer.instance.running) ...[
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: '复制端点',
                        visualDensity: VisualDensity.compact,
                        onPressed: _copyEndpoint,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '在 Claude Desktop / Cursor 等工具中配置：\n'
                  '{"mcpServers": {"IriX": {"url": '
                  '"http://127.0.0.1:${_mcpPortController.text}/mcp"}}}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// 从实例 logs/ 文件夹挑选日志文件的对话框。
///
/// 列出目录下所有 .log 与 .log.gz 文件（按修改时间倒序），
/// 点击文件后返回其绝对路径。
class _ServerLogPickerDialog extends StatefulWidget {
  final String rootPath;

  const _ServerLogPickerDialog({required this.rootPath});

  @override
  State<_ServerLogPickerDialog> createState() => _ServerLogPickerDialogState();
}

class _ServerLogPickerDialogState extends State<_ServerLogPickerDialog> {
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logsDir = Directory(p.join(widget.rootPath, 'logs'));
      if (!await logsDir.exists()) {
        if (!mounted) return;
        setState(() {
          _entries = [];
          _loading = false;
          _error = 'logs/ 文件夹不存在: ${logsDir.path}';
        });
        return;
      }
      final files =
          logsDir.listSync(recursive: false).whereType<File>().where((f) {
            final name = p.basename(f.path).toLowerCase();
            return name.endsWith('.log') || name.endsWith('.log.gz');
          }).toList()..sort((a, b) {
            final am = a.statSync().modified;
            final bm = b.statSync().modified;
            final cmp = bm.compareTo(am);
            return cmp != 0 ? cmp : a.path.compareTo(b.path);
          });
      if (!mounted) return;
      setState(() {
        _entries = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _error = '读取日志文件夹失败: $e';
      });
    }
  }

  static String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.manage_search, size: 20),
          const SizedBox(width: 8),
          const Text('选择日志文件（logs/）'),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            visualDensity: VisualDensity.compact,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 320,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : _entries.isEmpty
            ? Center(
                child: Text(
                  'logs/ 文件夹内没有 .log / .log.gz 文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final file = _entries[index] as File;
                  final stat = file.statSync();
                  final name = p.basename(file.path);
                  final isGz = name.toLowerCase().endsWith('.gz');
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isGz ? Icons.compress : Icons.description_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_sizeLabel(stat.size)} · '
                      '${stat.modified.year}-${stat.modified.month.toString().padLeft(2, '0')}-${stat.modified.day.toString().padLeft(2, '0')} '
                      '${stat.modified.hour.toString().padLeft(2, '0')}:${stat.modified.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    trailing: isGz
                        ? null
                        : const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).pop(file.path),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 添加 / 编辑模型对话框。
class _ModelEditDialog extends StatefulWidget {
  final AiModelConfig? model;

  const _ModelEditDialog({this.model});

  @override
  State<_ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<_ModelEditDialog> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _contextController = TextEditingController();
  final _embeddingController = TextEditingController();

  String? _nameError;
  String? _baseUrlError;
  String? _contextError;

  bool get _isEdit => widget.model != null;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    if (model != null) {
      _nameController.text = model.name;
      _baseUrlController.text = model.baseUrl;
      _apiKeyController.text = model.apiKey;
      _contextController.text = '${model.contextWindow}';
      _embeddingController.text = model.embeddingModel ?? '';
    } else {
      _contextController.text = '${AiSettings.defaultContextWindow}';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _contextController.dispose();
    _embeddingController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final contextWindow = int.tryParse(_contextController.text.trim());
    setState(() {
      _nameError = name.isEmpty ? '请输入模型名称' : null;
      _baseUrlError = baseUrl.isEmpty ? '请输入服务地址' : null;
      _contextError = (contextWindow == null || contextWindow < 256)
          ? '上下文窗口需 ≥ 256'
          : null;
    });
    if (_nameError != null || _baseUrlError != null || _contextError != null) {
      return;
    }
    final existing = widget.model;
    final model = AiModelConfig(
      id:
          existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name,
      baseUrl: baseUrl,
      apiKey: _apiKeyController.text.trim(),
      contextWindow: contextWindow!,
      embeddingModel: _embeddingController.text.trim().isEmpty
          ? null
          : _embeddingController.text.trim(),
    );
    Navigator.of(context).pop(model);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑模型' : '添加模型'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                autofocus: !_isEdit,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '模型名称',
                  hintText: 'deepseek-chat',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '服务地址 (Base URL)',
                  hintText: 'https://api.deepseek.com/v1',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _baseUrlError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'API 密钥',
                  hintText: '本地 Ollama 可留空',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contextController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '上下文窗口（token）',
                  hintText: '例如 8192 / 32768 / 65536',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _contextError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _embeddingController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Embedding 模型（可选，知识库用）',
                  hintText: '如 text-embedding-3-small；留空则用模型本身',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '对话接近上下文窗口上限时，会自动将较早的对话交给 AI 压缩成摘要，'
                '以节省 token 并保持长期对话连贯。\n'
                '知识库（RAG）使用 Embedding 模型生成向量，'
                '配置后即可在 AI 设置中导入 .txt/.md 文档。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(_isEdit ? '保存' : '添加')),
      ],
    );
  }
}
