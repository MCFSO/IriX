// AI 助手页面与可复用聊天面板
// 聊天式界面：用户提问 → 模型回答/调用工具；
// 敏感工具（执行命令、启停实例等）会弹出权限申请卡片，等待用户允许/拒绝。
//
// AiChatController 持有会话与事件列表（ChangeNotifier），
// AiChatPanel 是可复用的聊天面板（导航栏 AI 页与实例详情页侧栏共用）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ai_assistant_service.dart';
import '../services/ai_settings.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

/// 一次 AI 聊天的 UI 状态（事件列表 + 会话）。
class AiChatController extends ChangeNotifier {
  AiChatController({required this.conversation});

  final AiConversation conversation;

  /// 展示用事件列表。
  final List<AiEvent> events = [];

  /// 是否已完成 AI 配置。
  bool configured = false;

  Future<void> checkConfigured() async {
    final baseUrl = await AiSettings.getBaseUrl();
    final model = await AiSettings.getModel();
    final ok = baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;
    if (configured != ok) {
      configured = ok;
      notifyListeners();
    }
  }

  void _onEvent(AiEvent event) {
    events.add(event);
    notifyListeners();
  }

  /// 发送一条用户消息并运行一轮 agent 循环。
  Future<void> send(AppState state, String text) async {
    if (conversation.running) return;
    _onEvent(AiEvent.user(text));
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
/// 顶部显示关闭按钮（用于侧栏场景）。
class AiChatPanel extends StatefulWidget {
  final AiChatController controller;
  final VoidCallback? onClose;

  const AiChatPanel({super.key, required this.controller, this.onClose});

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.checkConfigured();
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
    _input.clear();
    _scrollToBottom();
    await widget.controller.send(context.read<AppState>(), text);
  }

  Future<void> _openSettings() async {
    await showAppDialog<void>(context, (_) => const _AiSettingsDialog());
    await widget.controller.checkConfigured();
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
            Expanded(
              child: controller.configured
                  ? _buildChat(conversation)
                  : _buildSetupPrompt(),
            ),
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
          Icon(
            Icons.smart_toy_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI 助手',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
            tooltip: 'AI 设置',
            visualDensity: VisualDensity.compact,
            onPressed: _openSettings,
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

  Widget _buildSetupPrompt() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('AI 助手未配置', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '配置 OpenAI 兼容 API 后可使用。\n敏感操作会先向你申请权限。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('配置 AI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(AiConversation conversation) {
    final controller = widget.controller;
    if (controller.events.isEmpty) {
      return Center(
        child: Text(
          '让 AI 帮你分析这个实例的日志、报错…',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
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
            child: Text(event.text ?? '', style: const TextStyle(height: 1.5)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !conversation.running,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: '向 AI 提问…',
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
            tooltip: '发送',
            onPressed: conversation.running ? null : _send,
            icon: const Icon(Icons.send, size: 20),
          ),
        ],
      ),
    );
  }
}

/// 导航栏 AI 分区页。
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
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final conversation = _controller.conversation;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conversation.running)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      tooltip: '停止',
                      onPressed: conversation.cancel,
                    ),
                  if (!conversation.running && _controller.events.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '清空对话',
                      onPressed: _controller.reset,
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AiChatPanel(controller: _controller),
    );
  }
}

/// AI 连接配置对话框。
class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog();

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final baseUrl = await AiSettings.getBaseUrl();
    final apiKey = await AiSettings.getApiKey();
    final model = await AiSettings.getModel();
    if (!mounted) return;
    _baseUrlController.text = baseUrl;
    _apiKeyController.text = apiKey;
    _modelController.text = model;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AiSettings.setBaseUrl(_baseUrlController.text);
    await AiSettings.setApiKey(_apiKeyController.text);
    await AiSettings.setModel(_modelController.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _baseUrlController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '服务地址 (Base URL)',
                  hintText: 'https://api.deepseek.com/v1',
                  border: OutlineInputBorder(),
                  isDense: true,
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
                controller: _modelController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: 'deepseek-chat',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '兼容 OpenAI Chat Completions 接口的服务均可使用，'
                '例如 DeepSeek / OpenAI / Kimi / 通义 / 本地 Ollama。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
