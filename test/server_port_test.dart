// server.properties 端口读取测试

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/ofrp_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('irix_frp_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File writeServerProperties(String content) {
    final file = File(p.join(tempDir.path, 'server.properties'));
    file.writeAsStringSync(content);
    return file;
  }

  test('文件不存在时返回 null', () {
    expect(readInstanceServerPort(tempDir.path), isNull);
  });

  test('读取 server-port 数值', () {
    writeServerProperties(
      'motd=A Minecraft Server\nserver-port=25570\nmax-players=20\n',
    );
    expect(readInstanceServerPort(tempDir.path), 25570);
  });

  test('server-port 为注释或带空格时正确解析', () {
    writeServerProperties('#server-port=1\nserver-port = 25565\n');
    expect(readInstanceServerPort(tempDir.path), 25565);
  });

  test('文件存在但未配置 server-port 时返回默认 25565', () {
    writeServerProperties('motd=hello\n');
    expect(readInstanceServerPort(tempDir.path), 25565);
  });

  test('端口值非法时返回默认 25565', () {
    writeServerProperties('server-port=abc\n');
    expect(readInstanceServerPort(tempDir.path), 25565);
  });
}
