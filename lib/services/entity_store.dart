// 实体持久化存储通用基类
//
// 抽取 instance_store / node_store / cluster_instance_store 三者的重复样板：
// 内存缓存、缓存检查 + try/catch 兜底、增删改时同步缓存。
//
// 子类只需提供三件事：行 ↔ 实体转换（[fromDbRow] / [toDbRow]）、主键提取
// （[idOf]），以及对 [DatabaseManager] 的四条 CRUD 委托（[fetchAll] /
// [insertRow] / [deleteRow] / [updateRow]）。缓存字段用 [cache] 暴露给子类，
// 以便 [InstanceStore] 等需要自定义字段更新的子类直接读写。

import 'package:flutter/foundation.dart';

abstract class EntityStore<T> {
  /// 内存缓存：首次加载后保留，避免每次操作都重新查询数据库。
  /// 为 null 表示尚未加载过（区别于已加载但列表为空的情况）。
  @protected
  List<T>? cache;

  /// 将数据库行记录转换为实体 [T]。
  T fromDbRow(Map<String, dynamic> row);

  /// 将实体 [T] 转换为数据库行记录。
  Map<String, dynamic> toDbRow(T entity);

  /// 提取实体的主键（用于缓存匹配与删除/更新定位）。
  String idOf(T entity);

  /// 从数据库查询全部行记录。
  Future<List<Map<String, dynamic>>> fetchAll();

  /// 将一行记录插入数据库。
  Future<void> insertRow(Map<String, dynamic> row);

  /// 按主键从数据库删除一行记录。
  Future<void> deleteRow(String id);

  /// 按主键更新一行记录（[row] 为完整行）。
  Future<void> updateRow(String id, Map<String, dynamic> row);

  /// 用于错误日志的存储名（如 'instances' / 'nodes'）。
  String get storeLabel;

  /// 加载全部实体。
  ///
  /// 返回缓存副本，避免外部直接修改影响内部缓存。
  Future<List<T>> loadAll() async {
    if (cache != null) {
      return List<T>.of(cache!);
    }
    try {
      final rows = await fetchAll();
      cache = rows.map(fromDbRow).toList();
      return List<T>.of(cache!);
    } catch (e) {
      debugPrint('Failed to load $storeLabel: $e');
      return cache ?? [];
    }
  }

  /// 添加实体并持久化，返回被添加的实体。
  Future<T> add(T entity) async {
    try {
      await insertRow(toDbRow(entity));
      cache?.add(entity);
      return entity;
    } catch (e) {
      debugPrint('Failed to add $storeLabel: $e');
      return entity;
    }
  }

  /// 按主键删除实体并持久化。
  Future<void> remove(String id) async {
    try {
      await deleteRow(id);
      cache?.removeWhere((e) => idOf(e) == id);
    } catch (e) {
      debugPrint('Failed to remove $storeLabel: $e');
    }
  }

  /// 更新实体并持久化（整行覆盖缓存中的旧实体）。
  Future<void> update(T entity) async {
    final id = idOf(entity);
    try {
      await updateRow(id, toDbRow(entity));
      if (cache != null) {
        final index = cache!.indexWhere((e) => idOf(e) == id);
        if (index >= 0) {
          cache![index] = entity;
        }
      }
    } catch (e) {
      debugPrint('Failed to update $storeLabel $id: $e');
    }
  }
}
