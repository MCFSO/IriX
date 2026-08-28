// nbt_ffi 集成测试
// 验证 Rust NBT FFI 封装（xmc_nbt）：SNBT 双向、二进制往返、树增删改查与搜索。
//
// 需要编译并复制 xmc_nbt 动态库（见 build_rust.bat / build_rust.sh）。
// 若动态库不在搜索路径，则用例自动跳过（CI 未复制库时不失败）。
//   flutter test test/nbt_ffi_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/nbt_ffi.dart';
import 'package:irix/services/nbt_service.dart';

/// 探测 xmc_nbt 动态库是否在搜索路径中（cwd / 项目根 / 平台目录）。
bool _libraryAvailable() {
  String libName;
  if (Platform.isWindows) {
    libName = 'xmc_nbt.dll';
  } else if (Platform.isMacOS) {
    libName = 'libxmc_nbt.dylib';
  } else {
    libName = 'libxmc_nbt.so';
  }
  final candidates = [
    p.join(Directory.current.path, libName),
    p.join(Directory.current.path, 'windows', 'runner', libName),
    p.join(Directory.current.path, 'linux', libName),
    p.join(Directory.current.path, 'macos', libName),
  ];
  return candidates.any((p) => File(p).existsSync());
}

void main() {
  final available = _libraryAvailable();
  final skipReason = available ? null : '未找到 xmc_nbt 动态库（先运行 build_rust）';

  group('nbt_ffi', () {
    test('SNBT 解析与往返', () async {
      // 注意：Compound 键按字母序规整化（BTreeMap），与原 mod 行为一致。
      const snbt = '{id:"minecraft:diamond",Count:1b,display:{Name:"hi"}}';
      final res = await NbtFfi.instance.request(op: 'parse_snbt', args: {'snbt': snbt});
      expect(
        res['snbt'],
        '{Count:1b,display:{Name:"hi"},id:"minecraft:diamond"}',
      );
    }, skip: skipReason);

    test('二进制 .nbt 往返（gzip 大端）', () async {
      const snbt = '{x:42,list:[1,2,3]}';
      final bytes = await NbtService.instance.toBinary(snbt, gzip: true);
      expect(bytes.length, greaterThan(2));
      // 应为 gzip 魔数。
      expect(bytes[0], 0x1F);
      expect(bytes[1], 0x8B);
      final back = await NbtService.instance.parseBinary(bytes);
      expect(back, '{list:[1,2,3],x:42}');
    }, skip: skipReason);

    test('树 to_tree / from_tree 往返', () async {
      const snbt = '{a:1,child:{b:"text"},arr:[10,20]}';
      final tree = await NbtService.instance.toTree(snbt);
      expect(tree.type, 'Compound');
      expect(tree.children.any((c) => c.name == 'a'), isTrue);
      final back = await NbtService.instance.fromTree(tree);
      expect(back, '{a:1,arr:[10,20],child:{b:"text"}}');
    }, skip: skipReason);

    test('get / set / delete 路径操作', () async {
      const snbt = '{a:{b:1},list:[10,20]}';
      var cur = snbt;
      cur = await NbtService.instance.set(cur, 'a/b', '99');
      expect(await NbtService.instance.get(cur, 'a/b'), '99');
      cur = await NbtService.instance.set(cur, 'a/c', '"new"');
      expect(await NbtService.instance.get(cur, 'a/c'), '"new"');
      cur = await NbtService.instance.delete(cur, 'list[0]');
      expect(await NbtService.instance.get(cur, 'list[0]'), '20');
    }, skip: skipReason);

    test('search 搜索路径', () async {
      const snbt = '{Enchantments:[{id:"minecraft:sharpness"}],Name:"sword"}';
      final hits = await NbtService.instance.search(snbt, 'sharpness', limit: 50);
      expect(hits.any((h) => h.contains('Enchantments')), isTrue);
    }, skip: skipReason);

    test('未知操作报错', () async {
      expect(
        () => NbtFfi.instance.request(op: 'unknown_op'),
        throwsA(
          isA<NbtFfiException>().having(
            (e) => e.toString(),
            'error',
            contains('不支持的 NBT 操作'),
          ),
        ),
      );
    });
  });
}
