// 市场 — 搜索页面
// 提供来源切换 (Modrinth / Hangar) + 搜索栏 + 筛选器 + 结果列表
import 'dart:async';
import 'package:flutter/material.dart';

import '../models/hangar.dart';
import '../models/modrinth.dart';
import '../services/hangar_api_service.dart';
import '../services/modrinth_api_service.dart';
import '../utils/apple_widgets.dart';
import 'hangar_detail_screen.dart';
import 'mod_detail_screen.dart';

/// 项目类型筛选选项
enum _ProjectTypeFilter {
  mod('Mod'),
  plugin('插件');

  final String label;
  const _ProjectTypeFilter(this.label);

  String? get apiValue => switch (this) {
        _ProjectTypeFilter.mod => 'mod',
        _ProjectTypeFilter.plugin => 'plugin',
      };
}

/// 排序方式
enum _SortIndex {
  relevance('相关度'),
  downloads('下载量'),
  follows('关注数'),
  newest('最新发布'),
  updated('最近更新');

  final String label;
  const _SortIndex(this.label);

  String get apiValue => switch (this) {
        _SortIndex.relevance => 'relevance',
        _SortIndex.downloads => 'downloads',
        _SortIndex.follows => 'follows',
        _SortIndex.newest => 'newest',
        _SortIndex.updated => 'updated',
      };
}

/// 市场搜索页面
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

/// 搜索结果的统一视图，屏蔽 Modrinth / Hangar 差异。
class _MarketHit {
  final String id;
  final String slug;
  final String title;
  final String description;
  final String? iconUrl;
  final int downloads;
  final int stars;
  final String category;
  final MarketplaceSource source;

  const _MarketHit({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    this.iconUrl,
    required this.downloads,
    required this.stars,
    required this.category,
    required this.source,
  });
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final ModrinthApiService _modrinthApi = ModrinthApiService();
  final HangarApiService _hangarApi = HangarApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  MarketplaceSource _source = MarketplaceSource.modrinth;

  List<_MarketHit> _hits = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  _ProjectTypeFilter _typeFilter = _ProjectTypeFilter.mod;
  _SortIndex _sortIndex = _SortIndex.relevance;
  String? _loaderFilter; // Modrinth 加载器（例如 'fabric', 'paper'）
  String? _gameVersionFilter; // 例如 '1.20.1'

  List<ModrinthTag> _loaders = [];
  List<ModrinthGameVersionTag> _gameVersions = [];

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _search();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _modrinthApi.dispose();
    _hangarApi.dispose();
    super.dispose();
  }

  /// 切换来源：清空当前结果并重新搜索。
  void _switchSource(MarketplaceSource source) {
    if (_source == source) return;
    setState(() {
      _source = source;
      _hits = [];
      _error = null;
      _hasMore = true;
    });
    _search();
  }

  static const _deprecatedLoaders = {
    'liteloader',
    "risugami's modloader",
  };

  Future<void> _loadTags() async {
    try {
      final loaders = await _modrinthApi.getLoaderTags();
      final versions = await _modrinthApi.getGameVersionTags();
      if (mounted) {
        setState(() {
          _loaders =
              loaders.where((l) => !_deprecatedLoaders.contains(l.name)).toList();
          _gameVersions = versions.where((v) => v.major).toList();
        });
      }
    } catch (_) {
      // 标签加载失败不阻塞主流程
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search();
    });
  }

  Future<void> _search() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hits = [];
      _hasMore = true;
    });

    try {
      final result = await _fetchPage(0, 20);
      setState(() {
        _hits = result.hits;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_hits.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await _fetchPage(_hits.length, 20);
      setState(() {
        _hits.addAll(result.hits);
        _hasMore = result.hasMore && result.hits.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (_) {
      setState(() => _isLoadingMore = false);
    }
  }

  /// 统一的分页获取入口，根据当前来源调用对应 API 并适配为 [_MarketHit]。
  Future<({List<_MarketHit> hits, bool hasMore})> _fetchPage(
    int offset,
    int limit,
  ) async {
    final query = _searchController.text.trim();
    switch (_source) {
      case MarketplaceSource.modrinth:
        final result = await _modrinthApi.search(
          query: query,
          facets: _buildFacets(),
          index: _sortIndex.apiValue,
          offset: offset,
          limit: limit,
        );
        final hits = result.hits
            .map((h) => _MarketHit(
                  id: h.projectId,
                  slug: h.slug,
                  title: h.title,
                  description: h.description,
                  iconUrl: h.iconUrl,
                  downloads: h.downloads,
                  stars: h.follows,
                  category: h.projectType,
                  source: MarketplaceSource.modrinth,
                ))
            .toList();
        return (hits: hits, hasMore: result.hits.length < result.totalHits);

      case MarketplaceSource.hangar:
        final sortMap = {
          _SortIndex.newest: 'newest',
          _SortIndex.updated: 'updated',
          _SortIndex.downloads: 'downloads',
          _SortIndex.follows: 'stars',
          _SortIndex.relevance: 'newest',
        };
        final platform = _loaderFilter;
        final result = await _hangarApi.search(
          query: query,
          platform: platform,
          sort: sortMap[_sortIndex] ?? 'newest',
          offset: offset,
          limit: limit,
        );
        final hits = result.hits
            .map((h) => _MarketHit(
                  id: h.slug,
                  slug: h.slug,
                  title: h.name,
                  description: h.description,
                  iconUrl: h.avatarUrl,
                  downloads: h.downloads,
                  stars: h.stars,
                  category: h.category,
                  source: MarketplaceSource.hangar,
                ))
            .toList();
        return (hits: hits, hasMore: _hits.length + hits.length < result.total);
    }
  }

  /// 构建 Modrinth facets 过滤条件
  /// facets 是 AND 关系，同一组内是 OR 关系
  List<List<String>> _buildFacets() {
    final facets = <List<String>>[];

    // 项目类型
    final type = _typeFilter.apiValue;
    if (type != null) {
      facets.add(['project_type:$type']);
    }

    // 加载器
    if (_loaderFilter != null) {
      facets.add(['categories:$_loaderFilter']);
    }

    // 游戏版本
    if (_gameVersionFilter != null) {
      facets.add(['versions:$_gameVersionFilter']);
    }

    return facets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildSourceSwitcher(),
          _buildSearchBar(),
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 来源切换 (Modrinth / Hangar)。
  Widget _buildSourceSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (final src in MarketplaceSource.values) ...[
            FilterChip(
              label: Text(src.label),
              selected: _source == src,
              showCheckmark: false,
              onSelected: (_) => _switchSource(src),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索 Mod / 插件...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _search();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
        onChanged: (value) {
          setState(() {});
          _onSearchChanged(value);
        },
        onSubmitted: (_) => _search(),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _buildTypeFilterChip(),
          _buildSortChip(),
          _buildLoaderChip(),
          _buildGameVersionChip(),
        ],
      ),
    );
  }

  Widget _buildTypeFilterChip() {
    return PopupMenuButton<_ProjectTypeFilter>(
      child: _filterChip('类型: ${_typeFilter.label}', active: true),
      onSelected: (value) {
        setState(() => _typeFilter = value);
        _search();
      },
      itemBuilder: (context) => _ProjectTypeFilter.values
          .map((e) => PopupMenuItem(
                value: e,
                textStyle: TextStyle(
                  color: e == _typeFilter
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                child: Text(e.label),
              ))
          .toList(),
    );
  }

  Widget _buildSortChip() {
    return PopupMenuButton<_SortIndex>(
      child: _filterChip('排序: ${_sortIndex.label}', active: true),
      onSelected: (value) {
        setState(() => _sortIndex = value);
        _search();
      },
      itemBuilder: (context) => _SortIndex.values
          .map((e) => PopupMenuItem(
                value: e,
                textStyle: TextStyle(
                  color: e == _sortIndex
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                child: Text(e.label),
              ))
          .toList(),
    );
  }

  Widget _buildLoaderChip() {
    return PopupMenuButton<String?>(
      child: _filterChip(
        _loaderFilter == null ? '加载器' : '加载器: $_loaderFilter',
        active: _loaderFilter != null,
      ),
      onSelected: (value) {
        setState(() => _loaderFilter = value);
        _search();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('全部')),
        ..._loaders.map((l) => PopupMenuItem(
              value: l.name,
              child: Text(l.name),
            )),
      ],
    );
  }

  Widget _buildGameVersionChip() {
    return PopupMenuButton<String?>(
      child: _filterChip(
        _gameVersionFilter == null ? '游戏版本' : 'MC $_gameVersionFilter',
        active: _gameVersionFilter != null,
      ),
      onSelected: (value) {
        setState(() => _gameVersionFilter = value);
        _search();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('全部')),
        ..._gameVersions.map((v) => PopupMenuItem(
              value: v.version,
              child: Text('${v.version} (${v.versionType})'),
            )),
      ],
    );
  }

  Widget _filterChip(String label, {bool active = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? Theme.of(context).colorScheme.primary : null,
              fontSize: 13,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_hits.isEmpty) {
      return const Center(child: Text('未找到相关项目'));
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _hits.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _hits.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final hit = _hits[index];
          return _SearchResultCard(
            hit: hit,
            onTap: () async {
              Widget screen;
              switch (hit.source) {
                case MarketplaceSource.modrinth:
                  screen = ModDetailScreen(
                    projectId: hit.id,
                    projectSlug: hit.slug,
                  );
                case MarketplaceSource.hangar:
                  screen = HangarDetailScreen(slug: hit.slug);
              }
              await pushPage<void>(
                context,
                (_) => screen,
              );
            },
          );
        },
      ),
    );
  }
}

/// 搜索结果卡片
class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.hit, required this.onTap});

  final _MarketHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hit.iconUrl != null && hit.iconUrl!.isNotEmpty
                    ? Image.network(
                        hit.iconUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _placeholderIcon(theme),
                      )
                    : _placeholderIcon(theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hit.description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _infoChip(
                            '${_formatNumber(hit.downloads)} 下载', Icons.download),
                        _infoChip(
                            '${_formatNumber(hit.stars)} 收藏', Icons.star),
                        _infoChip(hit.category, Icons.category),
                        _infoChip(hit.source.label, Icons.cloud),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon(ThemeData theme) {
    return Container(
      width: 64,
      height: 64,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.extension, color: theme.colorScheme.outline),
    );
  }

  Widget _infoChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10),
          const SizedBox(width: 2),
          Text(text, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
