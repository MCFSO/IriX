// Java 管理移植的单元测试（纯 Dart，不依赖 Rust 动态库）
//
// 覆盖 HMCL 移植过来的关键逻辑：
// - JavaInfo.parseVersion（HMCL JavaInfo.parseVersion）
// - JavaInfo.normalizeVendor（HMCL JavaInfo.normalizeVendor）
// - JavaInfo.fromReleaseFile（HMCL JavaInfo.fromReleaseFile）
// - JavaArchitecture.parseArchName（HMCL Architecture.parseArchName）
// - JavaRuntime 排序与比较（HMCL JavaRuntime.compareTo）
// - JavaManifest 往返序列化（HMCL JavaManifest.Serializer）

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/java_runtime.dart';
import 'package:irix/services/java/java_repository.dart';

void main() {
  group('JavaInfo.parseVersion', () {
    test('1.x 前缀按 legacy 规则取大版本', () {
      expect(JavaInfo.parseVersion('1.8.0_392'), 8);
      expect(JavaInfo.parseVersion('1.7.0'), 7);
      expect(JavaInfo.parseVersion('1.6.0_45'), 6);
    });

    test('现代版本号直接取首位数字段', () {
      expect(JavaInfo.parseVersion('17.0.9'), 17);
      expect(JavaInfo.parseVersion('21'), 21);
      expect(JavaInfo.parseVersion('25.0.1'), 25);
      expect(JavaInfo.parseVersion('11.0.20.1'), 11);
    });

    test('无法解析时返回 -1（HMCL 的兜底行为）', () {
      expect(JavaInfo.parseVersion(''), -1);
      expect(JavaInfo.parseVersion('abc'), -1);
      expect(JavaInfo.parseVersion('1.'), -1);
      // 超出 int 范围 → HMCL 捕获异常返回 -1
      expect(JavaInfo.parseVersion('99999999999999999999'), -1);
    });
  });

  group('JavaInfo.normalizeVendor', () {
    test('复刻 HMCL 的厂商映射表', () {
      expect(JavaInfo.normalizeVendor('Oracle Corporation'), 'Oracle');
      expect(JavaInfo.normalizeVendor('Azul Systems, Inc.'), 'Azul');
      expect(JavaInfo.normalizeVendor('Eclipse Adoptium'), 'Adoptium');
      expect(JavaInfo.normalizeVendor('Amazon.com Inc.'), 'Amazon');
      expect(JavaInfo.normalizeVendor('IBM Corporation'), 'IBM');
      expect(JavaInfo.normalizeVendor('Eclipse OpenJ9'), 'IBM');
      expect(
        JavaInfo.normalizeVendor('International Business Machines Corporation'),
        'IBM',
      );
    });

    test('N/A 与 null 归一化为 null，未知厂商原样返回', () {
      expect(JavaInfo.normalizeVendor('N/A'), isNull);
      expect(JavaInfo.normalizeVendor(null), isNull);
      expect(JavaInfo.normalizeVendor('Some Vendor'), 'Some Vendor');
    });
  });

  group('JavaInfo.fromReleaseFile', () {
    test('解析标准 release 文件', () {
      const content = '''
JAVA_VERSION="17.0.9"
OS_ARCH="amd64"
OS_NAME="Windows"
IMPLEMENTOR="Eclipse Adoptium"
IMPLEMENTOR_VERSION="Temurin-17.0.9+9"
''';
      final info = JavaInfo.fromReleaseFile(content);
      expect(info, isNotNull);
      expect(info!.version, '17.0.9');
      expect(info.parsedVersion, 17);
      expect(info.architecture, JavaArchitecture.x86_64);
      expect(info.normalizedVendor, 'Adoptium');
    });

    test('BSD 移植版：OS_NAME 为空 + OpenJDK BSD Porting Team → FreeBSD', () {
      const content = '''
JAVA_VERSION="11.0.2"
OS_ARCH="aarch64"
OS_NAME=""
IMPLEMENTOR="OpenJDK BSD Porting Team"
''';
      final info = JavaInfo.fromReleaseFile(content);
      expect(info, isNotNull);
      expect(info!.osName, 'FreeBSD');
      expect(info.architecture, JavaArchitecture.arm64);
    });

    test('缺少 JAVA_VERSION 返回 null', () {
      expect(JavaInfo.fromReleaseFile('OS_ARCH="amd64"'), isNull);
    });
  });

  group('JavaArchitecture.parseArchName', () {
    test('常见别名归一化', () {
      expect(JavaArchitecture.parseArchName('amd64'), JavaArchitecture.x86_64);
      expect(JavaArchitecture.parseArchName('x86_64'), JavaArchitecture.x86_64);
      expect(JavaArchitecture.parseArchName('x64'), JavaArchitecture.x86_64);
      expect(JavaArchitecture.parseArchName('aarch64'), JavaArchitecture.arm64);
      expect(JavaArchitecture.parseArchName('arm64'), JavaArchitecture.arm64);
      // Windows 上 os.arch 常见值为 x86
      expect(JavaArchitecture.parseArchName('x86'), JavaArchitecture.x86);
      expect(JavaArchitecture.parseArchName('i386'), JavaArchitecture.x86);
    });

    test('未知或空值 → unknown', () {
      expect(JavaArchitecture.parseArchName(null), JavaArchitecture.unknown);
      expect(JavaArchitecture.parseArchName(''), JavaArchitecture.unknown);
      expect(JavaArchitecture.parseArchName('sparc'), JavaArchitecture.unknown);
    });
  });

  group('JavaRuntime', () {
    JavaRuntime make({
      required String version,
      required String binary,
      String arch = 'amd64',
      bool isManaged = false,
      bool isJDK = true,
      String? vendor = 'Eclipse Adoptium',
    }) {
      return JavaRuntime(
        binary: binary,
        info: JavaInfo(
          version: version,
          architecture: JavaArchitecture.parseArchName(arch),
          vendor: vendor,
        ),
        isJDK: isJDK,
        isManaged: isManaged,
      );
    }

    test('相等性基于可执行文件路径（HMCL 同款语义）', () {
      final a = make(version: '17.0.9', binary: r'C:\a\bin\java.exe');
      final b = make(version: '21.0.1', binary: r'C:\a\bin\java.exe');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('排序：受管优先，其次大版本升序', () {
      final system = make(version: '8.0.392', binary: r'C:\s\bin\java.exe');
      final managed = make(
        version: '17.0.9',
        binary: r'C:\m\bin\java.exe',
        isManaged: true,
      );
      final list = [managed, system]..sort();
      // 受管在前（HMCL compareTo 第一条规则）。
      expect(list.first.isManaged, isTrue);
    });

    test('displayTitle 拼装为「厂商 JDK/JRE 版本」', () {
      final jdk = make(version: '17.0.9', binary: r'C:\a\bin\java.exe');
      final jre = make(
        version: '8.0.392',
        binary: r'C:\b\bin\java.exe',
        isJDK: false,
      );
      expect(jdk.displayTitle, 'Adoptium JDK 17.0.9');
      expect(jre.displayTitle, 'Adoptium JRE 8.0.392');
    });

    test('javaHome 为可执行文件上两级目录', () {
      // 两种分隔符风格都要通过，且结果与运行平台无关：
      // 早期实现用默认 p.dirname，在 Linux CI 上解析 Windows 路径会得到 '.'。
      final win = make(version: '17', binary: r'C:\jdk-17\bin\java.exe');
      expect(win.javaHome, r'C:\jdk-17');

      final nix = make(version: '17', binary: '/usr/lib/jvm/jdk-17/bin/java');
      expect(nix.javaHome, '/usr/lib/jvm/jdk-17');
    });
  });

  group('JavaManifest', () {
    test('往返序列化保留关键字段', () {
      final manifest = JavaManifest(
        name: 'jdk-17',
        info: const JavaInfo(
          version: '17.0.9',
          architecture: JavaArchitecture.x86_64,
          vendor: 'Eclipse Adoptium',
          osName: 'Windows',
        ),
        update: {'provider': 'adoptium', 'component': 'jdk'},
      );

      final parsed = JavaManifest.tryParse(jsonEncode(manifest.toJson()));

      expect(parsed, isNotNull);
      expect(parsed!.info.version, '17.0.9');
      expect(parsed.info.parsedVersion, 17);
      expect(parsed.info.architecture, JavaArchitecture.x86_64);
      expect(parsed.info.normalizedVendor, 'Adoptium');
      expect(parsed.name, 'jdk-17');
      expect(parsed.update, isNotNull);
      expect(parsed.update!['provider'], 'adoptium');
    });

    test('缺少 java.version 时解析失败返回 null', () {
      expect(JavaManifest.tryParse('{"os.arch":"amd64"}'), isNull);
    });

    test('非法 JSON 返回 null 而不抛异常', () {
      expect(JavaManifest.tryParse('not json at all'), isNull);
      expect(JavaManifest.tryParse('{}'), isNull);
    });
  });
}
