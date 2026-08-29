import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';

class ArchiveViewerScreen extends StatefulWidget {
  final String filePath;

  const ArchiveViewerScreen({required this.filePath, super.key});

  @override
  State<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends State<ArchiveViewerScreen> {
  late final Future<List<ArchiveFile>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    final l = AppLocalizations.of(context);
    _entriesFuture = _loadArchive(l);
  }

  Future<List<ArchiveFile>> _loadArchive(AppLocalizations l) async {
    final file = File(widget.filePath);
    if (!await file.exists()) {
      throw Exception(l.archive_fileNotFound(widget.filePath));
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.toList();
  }

  Future<void> _extractEntry(ArchiveFile entry) async {
    final l = AppLocalizations.of(context);
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l.archive_selectExtractDir,
    );
    if (dir == null || !mounted) return;

    try {
      final outputPath = p.join(dir, entry.name);
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(entry.content as List<int>);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.archive_extracted(entry.name))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.archive_extractFailed(e.toString()))));
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes == 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    ArchiveFile entry,
  ) {
    final l = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final overlayRect = Rect.fromPoints(
      overlay.localToGlobal(Offset.zero),
      overlay.localToGlobal(overlay.size.bottomRight(Offset.zero)),
    );

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        overlayRect,
      ),
        items: [
        PopupMenuItem(
          value: 'extract',
          child: Row(
            children: [
              const Icon(Icons.unarchive, size: 18),
              const SizedBox(width: 10),
              Text(l.archive_extractTo),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'extract') {
        _extractEntry(entry);
      }
    });
  }

  IconData _entryIcon(String name) {
    if (name.endsWith('/')) return Icons.folder;
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.class':
        return Icons.code;
      case '.jar':
      case '.zip':
        return Icons.archive;
      case '.json':
        return Icons.data_object;
      case '.xml':
      case '.yml':
      case '.yaml':
        return Icons.settings;
      case '.properties':
      case '.mf':
        return Icons.tune;
      case '.txt':
      case '.log':
        return Icons.description;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
        return Icons.image;
      case '.dll':
      case '.so':
      case '.dylib':
        return Icons.memory;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          p.basename(widget.filePath),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<List<ArchiveFile>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.broken_image_outlined,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.archive_cannotOpen,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.archive_invalidArchiveHint,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final entries = snapshot.data!;
          return Column(
            children: [
              _buildBreadcrumb(),
              const Divider(height: 1),
              _buildColumnHeaders(l),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(child: Text(l.archive_emptyArchive))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            _buildEntryRow(entries[index]),
                      ),
              ),
              const Divider(height: 1),
              _buildStatusBar(entries.length, l),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.archive_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.filePath,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaders(AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 28),
          Expanded(
            flex: 3,
            child: Text(
              l.archive_colName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              l.archive_colSize,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l.archive_colModified,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(ArchiveFile entry) {
    final theme = Theme.of(context);
    final name = entry.name;

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, entry);
      },
      child: InkWell(
        onTap: () => _extractEntry(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(_entryIcon(name), size: 18, color: Colors.grey[400]),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  _formatSize(entry.size),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatDate(entry.lastModDateTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(int count, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [Text(l.archive_entryCount(count), style: const TextStyle(fontSize: 12))],
      ),
    );
  }
}
