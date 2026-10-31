// jar 元数据扫描的 FFI 集成测试
//
// 验证 Dart → Rust（xmc_file_ops.dll 的 scan_jar_meta）链路：
// 构造一个临时 jar，扫描后应拿回 plugin.yml 里的名称与类型。
//
// 前置条件：动态库已编译并复制到项目根目录或 windows/runner/
// （运行 build_rust.bat 或 cargo build --release 后复制）。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/jar_metadata_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_jar_meta_ffi');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 用 archive 包写一个最小 jar（zip）。
  String writeJar(String name, Map<String, List<int>> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      final bytes = entry.value;
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    final path = p.join(tempDir.path, name);
    File(path).writeAsBytesSync(encoded);
    return path;
  }

  test('扫描 Bukkit 插件：名称与类型正确', () async {
    final jar = writeJar('demo-plugin.jar', {
      'plugin.yml': utf8.encode(
        'name: DemoPlugin\ndescription: Demo description\nversion: 1.0\n',
      ),
    });

    final metas = await JarMetadataService.readAllInBackground([jar]);
    expect(metas, hasLength(1));
    expect(metas.single.kind, JarKind.plugin);
    expect(metas.single.name, 'DemoPlugin');
    expect(metas.single.description, 'Demo description');
  });

  test('扫描 Fabric Mod：取最大尺寸图标', () async {
    final jar = writeJar('demo-mod.jar', {
      'fabric.mod.json': utf8.encode(
        '{"name":"Demo Mod","description":"Desc",'
        '"icon":{"64":"assets/64.png","128":"assets/128.png"}}',
      ),
      'assets/64.png': [1, 2, 3],
      'assets/128.png': [4, 5, 6],
    });

    final metas = await JarMetadataService.readAllInBackground([jar]);
    expect(metas.single.kind, JarKind.fabric);
    expect(metas.single.name, 'Demo Mod');
    expect(metas.single.iconBytes, isNotNull);
    expect(metas.single.iconBytes!.length, 3);
  });

  test('批量扫描保持顺序，坏文件不影响整批', () async {
    final good = writeJar('good.jar', {
      'plugin.yml': utf8.encode('name: Good\n'),
    });
    final broken = p.join(tempDir.path, 'broken.jar');
    File(broken).writeAsStringSync('not a zip');

    final metas = await JarMetadataService.readAllInBackground([broken, good]);
    expect(metas, hasLength(2));
    expect(metas[0].kind, JarKind.unknown);
    expect(metas[1].name, 'Good');
  });
}
