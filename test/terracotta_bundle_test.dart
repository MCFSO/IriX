// 陶瓦联机核心安装器单元测试。
//
// 用合成的 tar.gz（内容与我们声明的 SHA-512 一致）验证：
// 安装 → 判定就绪 → 文件被篡改 → 判定未安装 → 旧版本目录识别与清理。
// 真实官方包不在 CI 里下载（体积与网络原因），这里只验证安装逻辑本身。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/terracotta/terracotta_bundle.dart';
import 'package:irix/services/terracotta/terracotta_metadata.dart';
import 'package:path/path.dart' as p;

/// 用给定文件内容构造一个「元数据自洽」的包（摘要由内容算出）。
TerracottaBundle buildBundle(
  String rootPath,
  Map<String, Uint8List> contents, {
  String version = '0.4.2',
  String classifier = 'windows-x86_64',
}) {
  final files = {
    for (final entry in contents.entries)
      entry.key: crypto.sha512.convert(entry.value).toString(),
  };
  return TerracottaBundle(
    version: version,
    classifier: classifier,
    rootPath: p.join(rootPath, version),
    package: TerracottaPackage(hash: 'pkg-hash', files: files),
  );
}

/// 把 [contents] 打包成官方风格的 tar.gz 字节。
Uint8List buildTarGz(Map<String, Uint8List> contents) {
  final archive = Archive();
  for (final entry in contents.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final tar = TarEncoder().encode(archive);
  return Uint8List.fromList(GZipEncoder().encode(tar));
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('irix-terracotta-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('安装前为未安装，安装后判定就绪，文件被篡改后重新判定未安装', () async {
    final classifier =
        TerracottaMetadata.currentClassifier() ?? 'windows-x86_64';
    final exeName = Platform.isWindows
        ? 'terracotta-0.4.2-$classifier.exe'
        : 'terracotta-0.4.2-$classifier';
    final contents = <String, Uint8List>{
      exeName: Uint8List.fromList(utf8.encode('fake terracotta core')),
      if (Platform.isWindows)
        'VCRUNTIME140.DLL': Uint8List.fromList(utf8.encode('fake vcruntime')),
    };

    final bundle = buildBundle(tempDir.path, contents, classifier: classifier);
    expect(bundle.executableName, exeName);
    expect(bundle.packageName, 'terracotta-0.4.2-$classifier-pkg.tar.gz');

    expect(await bundle.status(), TerracottaBundleStatus.notExist);

    final pkgPath = p.join(tempDir.path, bundle.packageName);
    File(pkgPath).writeAsBytesSync(buildTarGz(contents));
    await bundle.install(pkgPath);
    expect(await bundle.status(), TerracottaBundleStatus.ready);
    expect(File(bundle.executablePath).existsSync(), isTrue);

    // 篡改一个字节：摘要不再匹配 → 视为未安装。
    final exe = File(bundle.executablePath);
    final bytes = exe.readAsBytesSync();
    bytes[0] = bytes[0] ^ 0xFF;
    exe.writeAsBytesSync(bytes);
    expect(await bundle.status(), TerracottaBundleStatus.notExist);
  });

  test('安装包装了缺文件时抛 TerracottaInstallException 并清理目录', () async {
    final classifier =
        TerracottaMetadata.currentClassifier() ?? 'windows-x86_64';
    final exeName = Platform.isWindows
        ? 'terracotta-0.4.2-$classifier.exe'
        : 'terracotta-0.4.2-$classifier';
    final bundle = buildBundle(tempDir.path, {
      exeName: Uint8List.fromList(utf8.encode('core')),
      'EXTRA.DLL': Uint8List.fromList(utf8.encode('dll')),
    }, classifier: classifier);

    // 只打包 exe，缺 EXTRA.DLL。
    final pkgPath = p.join(tempDir.path, bundle.packageName);
    File(pkgPath).writeAsBytesSync(
      buildTarGz({exeName: Uint8List.fromList(utf8.encode('core'))}),
    );

    await expectLater(
      bundle.install(pkgPath),
      throwsA(isA<TerracottaInstallException>()),
    );
    expect(Directory(bundle.rootPath).existsSync(), isFalse);
  });

  test('内容与声明摘要不符时拒绝安装（防镜像投毒）', () async {
    final classifier =
        TerracottaMetadata.currentClassifier() ?? 'windows-x86_64';
    final exeName = Platform.isWindows
        ? 'terracotta-0.4.2-$classifier.exe'
        : 'terracotta-0.4.2-$classifier';
    final bundle = buildBundle(tempDir.path, {
      exeName: Uint8List.fromList(utf8.encode('expected')),
    }, classifier: classifier);

    final pkgPath = p.join(tempDir.path, bundle.packageName);
    File(pkgPath).writeAsBytesSync(
      buildTarGz({
        exeName: Uint8List.fromList(utf8.encode('tampered payload')),
      }),
    );

    await expectLater(
      bundle.install(pkgPath),
      throwsA(isA<TerracottaInstallException>()),
    );
  });

  test('本地包文件名必须与官方命名一致', () {
    final bundle = buildBundle(tempDir.path, {}, classifier: 'windows-x86_64');
    expect(
      bundle.isInvalidLocalBundle('D:/downloads/${bundle.packageName}'),
      isFalse,
    );
    expect(bundle.isInvalidLocalBundle('D:/downloads/terracotta.zip'), isTrue);
  });

  test('旧版本目录识别与清理：只删 <= 当前版本且不是当前版本的目录', () async {
    final parent = Directory(p.join(tempDir.path, 'terracotta'))
      ..createSync(recursive: true);
    Directory(p.join(parent.path, '0.4.1')).createSync();
    Directory(p.join(parent.path, '0.3.9')).createSync();
    Directory(p.join(parent.path, '0.5.0')).createSync();
    Directory(p.join(parent.path, 'not-a-version')).createSync();
    final bundle = buildBundle(parent.path, {
      'core': Uint8List.fromList([1, 2, 3]),
    });

    final legacy = await bundle.legacyVersionDirs();
    expect(legacy.map(p.basename).toSet(), {'0.4.1', '0.3.9'});
    expect(await bundle.status(), isNot(TerracottaBundleStatus.ready));

    await bundle.removeLegacyVersions();
    expect(Directory(p.join(parent.path, '0.4.1')).existsSync(), isFalse);
    expect(Directory(p.join(parent.path, '0.3.9')).existsSync(), isFalse);
    expect(Directory(p.join(parent.path, '0.5.0')).existsSync(), isTrue);
    expect(
      Directory(p.join(parent.path, 'not-a-version')).existsSync(),
      isTrue,
    );
  });

  test('元数据：包名/可执行文件/下载地址与版本一致', () {
    final classifier = TerracottaMetadata.currentClassifier();
    if (classifier == null) {
      return; // 不支持的平台跳过（CI 上不会发生）。
    }
    expect(TerracottaMetadata.packageName, endsWith('-$classifier-pkg.tar.gz'));
    final urls = TerracottaMetadata.resolveDownloadUrls();
    expect(urls, isNotEmpty);
    expect(urls.every((u) => u.contains(classifier)), isTrue);
    expect(urls.every((u) => u.endsWith('-pkg.tar.gz')), isTrue);
    expect(TerracottaMetadata.currentPackage(), isNotNull);
  });
}
