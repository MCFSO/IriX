// NBT 编辑服务
//
// 封装 xmc_nbt FFI，提供 Minecraft NBT 的解析/序列化与树编辑能力
// （复刻 AnkiNBT 的编辑功能，独立于 Minecraft 运行时）：
// - 二进制 .nbt（gzip 大端）<-> SNBT 文本双向转换；
// - 树路径增删改查与搜索；
// - 树 JSON（to_tree/from_tree）供 Flutter UI 渲染与编辑。
//
// 所有 FFI 调用经 NbtFfi 在后台 isolate 执行，不阻塞 UI。

import 'dart:convert';
import 'dart:typed_data';

import '../services/nbt_ffi.dart';

/// NBT 节点类型名（与 Rust 侧 TagType::name() 一致）。
class NbtType {
  static const byte = 'Byte';
  static const short = 'Short';
  static const int_ = 'Int';
  static const long = 'Long';
  static const float = 'Float';
  static const double_ = 'Double';
  static const byteArray = 'Byte[]';
  static const string = 'String';
  static const list = 'List';
  static const compound = 'Compound';
  static const intArray = 'Int[]';
  static const longArray = 'Long[]';

  /// 全部可选类型（用于新建节点时的选择）。
  static const all = [
    byte,
    short,
    int_,
    long,
    float,
    double_,
    byteArray,
    string,
    list,
    compound,
    intArray,
    longArray,
  ];

  /// 是否为标量（有单一 value，无 children）。
  static bool isScalar(String type) =>
      type == byte ||
      type == short ||
      type == int_ ||
      type == long ||
      type == float ||
      type == double_ ||
      type == string;

  /// 是否为数组（value 为数字列表）。
  static bool isArray(String type) =>
      type == byteArray || type == intArray || type == longArray;

  /// 是否为容器（含 children）。
  static bool isContainer(String type) => type == list || type == compound;
}

/// Dart 侧 NBT 树节点（与 Rust to_tree 输出结构一致）。
///
/// 根节点无 name；Compound 子节点带 name，List 子节点 name 为空。
/// 标量/数组节点用 [value]；容器节点用 [children]。
class NbtNode {
  /// 键名（Compound 子节点）；根节点与 List 子节点为空字符串。
  String name;

  /// 类型名（见 [NbtType]）。
  String type;

  /// 标量/数组的值（JSON 原生类型）；容器为 null。
  dynamic value;

  /// List 元素类型名（仅 List 节点有效）。
  String? elemType;

  /// 子节点（仅 Compound/List 有效）。
  List<NbtNode> children;

  NbtNode({
    required this.type,
    this.name = '',
    this.value,
    this.elemType,
    List<NbtNode>? children,
  }) : children = children ?? [];

  /// 是否为容器。
  bool get isContainer => NbtType.isContainer(type);

  /// 是否为标量。
  bool get isScalar => NbtType.isScalar(type);

  /// 是否为数组。
  bool get isArray => NbtType.isArray(type);

  /// 从 Rust 树 JSON 构造。
  factory NbtNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? NbtType.compound;
    return NbtNode(
      name: json['name'] as String? ?? '',
      type: type,
      value: json['value'],
      elemType: json['elem_type'] as String?,
      children: [
        for (final c in (json['children'] as List? ?? const []))
          NbtNode.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  /// 序列化为 Rust 树 JSON（供 from_tree）。
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': type};
    if (name.isNotEmpty) json['name'] = name;
    if (type == NbtType.list && elemType != null) {
      json['elem_type'] = elemType;
    }
    if (isContainer) {
      json['children'] = [for (final c in children) c.toJson()];
    } else {
      json['value'] = value;
    }
    return json;
  }

  NbtNode clone() => NbtNode(
        type: type,
        name: name,
        value: value,
        elemType: elemType,
        children: [for (final c in children) c.clone()],
      );
}

/// NBT 编辑服务（单例）。
class NbtService {
  static final NbtService instance = NbtService._();
  NbtService._();

  // === 基础编解码 ===

  /// 解析 SNBT 文本，返回规整化后的 SNBT（用于校验/格式化）。
  Future<String> parseSnbt(String snbt) async {
    final res = await NbtFfi.instance.request(op: 'parse_snbt', args: {'snbt': snbt});
    return res['snbt'] as String? ?? '';
  }

  /// 序列化为 SNBT。
  Future<String> toSnbt(String snbt) async {
    final res = await NbtFfi.instance.request(op: 'to_snbt', args: {'snbt': snbt});
    return res['snbt'] as String? ?? '';
  }

  /// 解析二进制 NBT（gzip 自动检测）。[bytes] 为原始字节。
  /// 返回 SNBT 文本。
  Future<String> parseBinary(Uint8List bytes) async {
    final b64 = base64Encode(bytes);
    final res = await NbtFfi.instance.request(op: 'parse_binary', args: {'data': b64});
    return res['snbt'] as String? ?? '';
  }

  /// 序列化为二进制 NBT。[gzip] 默认 true（与 Minecraft .nbt 一致）。
  /// 返回原始字节。
  Future<Uint8List> toBinary(String snbt, {bool gzip = true}) async {
    final res = await NbtFfi.instance.request(
      op: 'to_binary',
      args: {'snbt': snbt, if (!gzip) 'raw': true},
    );
    final b64 = res['data'] as String? ?? '';
    return base64Decode(b64);
  }

  // === 树模型 ===

  /// 将 SNBT 转为 Dart 树（根节点为 Compound，无 name）。
  Future<NbtNode> toTree(String snbt) async {
    final res = await NbtFfi.instance.request(op: 'to_tree', args: {'snbt': snbt});
    final tree = res['tree'] as Map<String, dynamic>? ?? {};
    return NbtNode.fromJson(tree);
  }

  /// 从 Dart 树重建 SNBT。
  Future<String> fromTree(NbtNode node) async {
    final res = await NbtFfi.instance.request(op: 'from_tree', args: {'tree': node.toJson()});
    return res['snbt'] as String? ?? '';
  }

  // === 路径操作 ===

  /// 取路径处节点的 SNBT。
  Future<String> get(String snbt, String path) async {
    final res = await NbtFfi.instance.request(op: 'get', args: {'snbt': snbt, 'path': path});
    return res['snbt'] as String? ?? '';
  }

  /// 设置路径处节点（value 为 SNBT 文本），返回更新后的 SNBT。
  Future<String> set(String snbt, String path, String valueSnbt) async {
    final res = await NbtFfi.instance.request(
      op: 'set',
      args: {'snbt': snbt, 'path': path, 'value': valueSnbt},
    );
    return res['snbt'] as String? ?? snbt;
  }

  /// 删除路径处节点，返回更新后的 SNBT。
  Future<String> delete(String snbt, String path) async {
    final res = await NbtFfi.instance.request(op: 'delete', args: {'snbt': snbt, 'path': path});
    return res['snbt'] as String? ?? snbt;
  }

  /// 搜索包含 [query] 的路径列表。
  Future<List<String>> search(String snbt, String query, {int limit = 200}) async {
    final res = await NbtFfi.instance.request(
      op: 'search',
      args: {'snbt': snbt, 'query': query, 'limit': limit},
    );
    final paths = res['paths'] as List? ?? const [];
    return paths.cast<String>();
  }

  // === 便捷：从字节直接到树 ===

  /// 解析二进制 NBT 并构造 Dart 树。
  Future<NbtNode> parseBinaryToTree(Uint8List bytes) async {
    final snbt = await parseBinary(bytes);
    return toTree(snbt);
  }

  /// 把 Dart 树序列化为二进制 NBT。
  Future<Uint8List> treeToBinary(NbtNode node, {bool gzip = true}) async {
    final snbt = await fromTree(node);
    return toBinary(snbt, gzip: gzip);
  }

  /// 创建一个指定类型的默认空节点。
  static NbtNode createDefault(String type, {String name = ''}) {
    switch (type) {
      case NbtType.byte:
        return NbtNode(type: type, name: name, value: 0);
      case NbtType.short:
        return NbtNode(type: type, name: name, value: 0);
      case NbtType.int_:
        return NbtNode(type: type, name: name, value: 0);
      case NbtType.long:
        return NbtNode(type: type, name: name, value: '0');
      case NbtType.float:
        return NbtNode(type: type, name: name, value: 0.0);
      case NbtType.double_:
        return NbtNode(type: type, name: name, value: 0.0);
      case NbtType.string:
        return NbtNode(type: type, name: name, value: '');
      case NbtType.byteArray:
        return NbtNode(type: type, name: name, value: <int>[]);
      case NbtType.intArray:
        return NbtNode(type: type, name: name, value: <int>[]);
      case NbtType.longArray:
        return NbtNode(type: type, name: name, value: <String>[]);
      case NbtType.list:
        return NbtNode(type: type, name: name, elemType: NbtType.compound, children: []);
      case NbtType.compound:
      default:
        return NbtNode(type: NbtType.compound, name: name, children: []);
    }
  }
}
