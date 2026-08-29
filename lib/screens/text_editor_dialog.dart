import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/font_settings.dart';
import '../utils/code_highlight.dart';

class TextEditorDialog extends StatefulWidget {
  final String filePath;
  const TextEditorDialog({required this.filePath, super.key});

  @override
  State<TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<TextEditorDialog> {
  late final HighlightTextEditingController _controller;
  final ScrollController _gutterScroll = ScrollController();
  final ScrollController _editorScroll = ScrollController();
  final List<String> _undoStack = [];
  String? _previousText;

  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = HighlightTextEditingController(fileName: widget.filePath);
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    _gutterScroll.dispose();
    _editorScroll.dispose();
    super.dispose();
  }

  void _loadFile() {
    try {
      final content = File(widget.filePath).readAsStringSync();
      _controller.text = content;
    } catch (e) {
      _error = e.toString();
    }
  }

  void _save() async {
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      if (mounted) {
        setState(() => _dirty = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    }
  }

  void _onChanged() {
    if (!_dirty) setState(() => _dirty = true);
    _undoStack.add(_previousText ?? '');
    _previousText = _controller.text;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final prev = _undoStack.removeLast();
    _controller.text = prev;
    _previousText = prev;
    _controller.selection = TextSelection.collapsed(offset: prev.length);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(_dirty),
          ),
          title: Text(fileName, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.isNotEmpty ? _undo : null,
              tooltip: l.textEditor_undo,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: l.common_save,
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.textEditor_cannotRead, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_error!, style: theme.textTheme.bodySmall),
                  ],
                ),
              )
            : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    final text = _controller.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    const lineH = 19.5;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 48,
            child: Container(
              color: const Color(0xFF1E1E1E),
              child: ListView.builder(
                controller: _gutterScroll,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lineCount,
                itemExtent: lineH,
                itemBuilder: (_, i) => Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontFamily: FontSettings.instance.terminalFamily,
                      fontSize: 13,
                      color: Color(0xFF6A737D),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (_gutterScroll.hasClients) {
                _gutterScroll.jumpTo(n.metrics.pixels);
              }
              return false;
            },
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              scrollController: _editorScroll,
              style: TextStyle(
                fontFamily: FontSettings.instance.terminalFamily,
                fontSize: 13,
                height: 1.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(8),
              ),
              onChanged: (_) => _onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showTextEditor(BuildContext context, String filePath) {
  return showDialog<bool>(
    context: context,
    builder: (_) => TextEditorDialog(filePath: filePath),
  );
}
