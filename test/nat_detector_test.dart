// NAT 检测单元测试：STUN Binding Request/Response 编解码。

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/nat_detector.dart';

void main() {
  group('StunPacket 编解码', () {
    test('无 CHANGE-REQUEST 的 Binding Request 结构正确', () {
      final packet = StunPacket(random: Random(42)).buildBindingRequest();
      expect(packet.length, 20);
      expect(
        (packet[0] << 8) | packet[1],
        0x0001,
        reason: '类型为 Binding Request',
      );
      expect((packet[2] << 8) | packet[3], 0, reason: '无属性时长度为 0');
      expect(
        (packet[4] << 24) | (packet[5] << 16) | (packet[6] << 8) | packet[7],
        0x2112A442,
        reason: 'magic cookie',
      );
    });

    test('CHANGE-REQUEST 属性编码（换端口 0x02 / 换 IP 0x04）', () {
      final codec = StunPacket(random: Random(42));
      final changePort = codec.buildBindingRequest(changePort: true);
      expect(changePort.length, 28);
      expect((changePort[20] << 8) | changePort[21], 0x0003, reason: '属性类型');
      expect((changePort[22] << 8) | changePort[23], 4, reason: '属性长度');
      expect(changePort[27], 0x02, reason: '仅换端口');
      final changeIp = codec.buildBindingRequest(changeIp: true);
      expect(changeIp[27], 0x04, reason: '仅换 IP');
      final both = codec.buildBindingRequest(changeIp: true, changePort: true);
      expect(both[27], 0x06, reason: 'IP+端口');
    });

    test('解析 XOR-MAPPED-ADDRESS 响应', () {
      final magic = 0x2112A442;
      final ip = [192, 168, 1, 100];
      final port = 55555;
      final builder = BytesBuilder()
        ..add([0x01, 0x01]) // Binding Success
        ..add([0x00, 0x0C]) // 长度 12
        ..add([
          (magic >> 24) & 0xFF,
          (magic >> 16) & 0xFF,
          (magic >> 8) & 0xFF,
          magic & 0xFF,
        ]);
      for (var i = 0; i < 12; i++) {
        builder.addByte(i);
      }
      builder
        ..add([0x00, 0x20]) // XOR-MAPPED-ADDRESS
        ..add([0x00, 0x08])
        ..add([0x00, 0x01]) // family IPv4
        ..add([(port >> 8) ^ ((magic >> 16) & 0xFF), port ^ (magic & 0xFF)])
        ..add([
          ip[0] ^ ((magic >> 24) & 0xFF),
          ip[1] ^ ((magic >> 16) & 0xFF),
          ip[2] ^ ((magic >> 8) & 0xFF),
          ip[3] ^ (magic & 0xFF),
        ]);
      final decoded = StunPacket().parseBindingResponse(builder.takeBytes());
      expect(decoded, '192.168.1.100:55555');
    });

    test('解析 MAPPED-ADDRESS 响应（明文）', () {
      final magic = 0x2112A442;
      final builder = BytesBuilder()
        ..add([0x01, 0x01])
        ..add([0x00, 0x0C]);
      builder.add([
        (magic >> 24) & 0xFF,
        (magic >> 16) & 0xFF,
        (magic >> 8) & 0xFF,
        magic & 0xFF,
      ]);
      for (var i = 0; i < 12; i++) {
        builder.addByte(i);
      }
      builder
        ..add([0x00, 0x01])
        ..add([0x00, 0x08])
        ..add([0x00, 0x01])
        ..add([0x04, 0xD2]) // 端口 1234
        ..add([10, 0, 0, 8]);
      final decoded = StunPacket().parseBindingResponse(builder.takeBytes());
      expect(decoded, '10.0.0.8:1234');
    });

    test('非法响应返回 null', () {
      expect(
        StunPacket().parseBindingResponse(
          Uint8List.fromList(List.filled(20, 0)),
        ),
        isNull,
        reason: '错误类型',
      );
      expect(
        StunPacket().parseBindingResponse(
          Uint8List.fromList(List.filled(5, 0)),
        ),
        isNull,
        reason: '长度不足',
      );
    });
  });

  group('NatDetectionResult', () {
    test('仅公网直连不需要 FRP', () {
      expect(
        const NatDetectionResult(
          type: NatType.openInternet,
          mappedAddress: null,
        ).needsFrp,
        false,
      );
      for (final type in [
        NatType.blocked,
        NatType.fullCone,
        NatType.restrictedCone,
        NatType.portRestrictedCone,
        NatType.symmetric,
      ]) {
        expect(
          NatDetectionResult(type: type, mappedAddress: null).needsFrp,
          true,
          reason: '$type 需要 FRP 建议',
        );
      }
    });
  });
}
