// NAT 类型检测（STUN，RFC 3489/5780 简化算法）
//
// 用于首次引导完成后判断用户网络环境，决定是否需要推荐 FRP 内网穿透：
// - 通过两个公共 STUN 服务器（stun.l.google.com / stun1.l.google.com）收发
//   Binding Request，配合 CHANGE-REQUEST 属性分类 NAT；
// - 纯 dart:io UDP 实现（RawDatagramSocket），无外部依赖；
// - 每次探测约 2~6 秒（受超时与网络影响），阻塞调用，请放在后台执行。

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// NAT 类型。
enum NatType {
  /// UDP 完全被阻断（无任何响应，可能是防火墙/纯 IPv6）。
  blocked('UDP 阻断'),

  /// 公网直连（无 NAT）。
  openInternet('公网直连'),

  /// 全锥形 NAT（任一外部主机可经映射回连）。
  fullCone('全锥形 NAT'),

  /// 受限锥形 NAT（仅允许与通讯过的外部 IP 回连，不校验端口）。
  restrictedCone('受限锥形 NAT'),

  /// 端口受限锥形 NAT（仅允许与通讯过的外部 IP:端口 回连）。
  portRestrictedCone('端口受限锥形 NAT'),

  /// 对称型 NAT（每次连接使用不同映射，最难穿透）。
  symmetric('对称型 NAT');

  const NatType(this.label);

  /// 中文展示标签。
  final String label;
}

/// 检测结果。
class NatDetectionResult {
  const NatDetectionResult({
    required this.type,
    required this.mappedAddress,
    this.uncertain = false,
  });

  final NatType type;

  /// 公网映射地址（如 1.2.3.4:5678）。
  final String? mappedAddress;

  /// 结果不确定（如第二台 STUN 服务器不可达）。
  final bool uncertain;

  /// 是否需要推荐 FRP：仅公网直连不需要。
  bool get needsFrp => type != NatType.openInternet;
}

/// STUN Binding Request / Response 编解码（纯函数，可单测）。
class StunPacket {
  static const int _magic = 0x2112A442;
  static const int _typeBindingRequest = 0x0001;
  static const int _typeBindingSuccess = 0x0101;
  static const int _attrMappedAddress = 0x0001;
  static const int _attrXorMappedAddress = 0x0020;
  static const int _attrChangeRequest = 0x0003;

  final Random _random;

  StunPacket({Random? random}) : _random = random ?? Random.secure();

  /// 构造 Binding Request；[changeIp]/[changePort] 对应 CHANGE-REQUEST 属性。
  Uint8List buildBindingRequest({
    bool changeIp = false,
    bool changePort = false,
  }) {
    final hasChange = changeIp || changePort;
    final body = BytesBuilder();
    if (hasChange) {
      var flags = 0;
      if (changePort) flags |= 0x02;
      if (changeIp) flags |= 0x04;
      body
        ..add([(_attrChangeRequest >> 8) & 0xFF, _attrChangeRequest & 0xFF])
        ..add([0x00, 0x04])
        ..add([0, 0, 0, flags]);
    }
    final payload = body.takeBytes();
    final packet = BytesBuilder()
      ..add([(_typeBindingRequest >> 8) & 0xFF, _typeBindingRequest & 0xFF])
      ..add([(payload.length >> 8) & 0xFF, payload.length & 0xFF])
      ..add([
        (_magic >> 24) & 0xFF,
        (_magic >> 16) & 0xFF,
        (_magic >> 8) & 0xFF,
        _magic & 0xFF,
      ]);
    for (var i = 0; i < 12; i++) {
      packet.addByte(_random.nextInt(256));
    }
    packet.add(payload);
    return packet.takeBytes();
  }

  /// 解析 Binding Success 响应，返回映射地址 "ip:port"；非法响应返回 null。
  String? parseBindingResponse(Uint8List data) {
    if (data.length < 20) return null;
    final type = (data[0] << 8) | data[1];
    if (type != _typeBindingSuccess) return null;
    final magic = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
    if (magic != _magic) return null;
    final length = (data[2] << 8) | data[3];
    var offset = 20;
    final end = (20 + length).clamp(20, data.length);
    while (offset + 4 <= end) {
      final attrType = (data[offset] << 8) | data[offset + 1];
      final attrLen = (data[offset + 2] << 8) | data[offset + 3];
      offset += 4;
      if (offset + attrLen > end) break;
      if (attrType == _attrXorMappedAddress && attrLen >= 8) {
        final family = data[offset + 1];
        if (family == 0x01 && attrLen >= 8) {
          final port =
              ((data[offset + 2] ^ ((_magic >> 16) & 0xFF)) << 8) |
              (data[offset + 3] ^ (_magic & 0xFF));
          final ip = [
            data[offset + 4] ^ ((_magic >> 24) & 0xFF),
            data[offset + 5] ^ ((_magic >> 16) & 0xFF),
            data[offset + 6] ^ ((_magic >> 8) & 0xFF),
            data[offset + 7] ^ (_magic & 0xFF),
          ];
          return '${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}:$port';
        }
      } else if (attrType == _attrMappedAddress && attrLen >= 8) {
        final family = data[offset + 1];
        if (family == 0x01 && attrLen >= 8) {
          final port = (data[offset + 2] << 8) | data[offset + 3];
          final ip = data.sublist(offset + 4, offset + 8);
          return '${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}:$port';
        }
      }
      offset += attrLen + (attrLen % 4 == 0 ? 0 : 4 - attrLen % 4);
    }
    return null;
  }
}

/// STUN 服务器。
class StunServer {
  const StunServer(this.host, this.port);

  final String host;
  final int port;
}

/// 默认使用 Google 公共 STUN 服务器（支持 CHANGE-REQUEST）。
const defaultStunServers = [
  StunServer('stun.l.google.com', 19302),
  StunServer('stun1.l.google.com', 19302),
];

/// NAT 检测器。
class NatDetector {
  NatDetector({
    this.servers = defaultStunServers,
    this.timeout = const Duration(seconds: 2),
  });

  final List<StunServer> servers;

  /// 单次 Binding 超时。
  final Duration timeout;

  /// 检测 NAT 类型（阻塞；建议在后台 isolate 执行）。
  Future<NatDetectionResult> detect() async {
    final codec = StunPacket();
    if (servers.isEmpty) {
      return const NatDetectionResult(
        type: NatType.blocked,
        mappedAddress: null,
      );
    }

    // Test I：主服务器绑定
    final r1 = await _binding(servers[0], codec);
    if (r1 == null) {
      return const NatDetectionResult(
        type: NatType.blocked,
        mappedAddress: null,
      );
    }

    // Test II：要求主服务器换 IP+端口 回包
    final r2 = await _binding(
      servers[0],
      codec,
      changeIp: true,
      changePort: true,
    );
    if (r2 != null) {
      return NatDetectionResult(type: NatType.openInternet, mappedAddress: r1);
    }

    // Test III：要求主服务器仅换端口回包
    final r3 = await _binding(servers[0], codec, changePort: true);
    if (r3 != null) {
      return NatDetectionResult(type: NatType.fullCone, mappedAddress: r1);
    }

    // 第二台服务器对比映射端口，区分对称 / 受限
    if (servers.length < 2) {
      return const NatDetectionResult(
        type: NatType.restrictedCone,
        mappedAddress: null,
        uncertain: true,
      );
    }
    final r4 = await _binding(servers[1], codec);
    if (r4 == null) {
      return NatDetectionResult(
        type: NatType.restrictedCone,
        mappedAddress: r1,
        uncertain: true,
      );
    }
    final port1 = _portOf(r1);
    final port4 = _portOf(r4);
    if (port1 == null || port4 == null || port1 != port4) {
      return NatDetectionResult(type: NatType.symmetric, mappedAddress: r1);
    }

    // 映射一致：第二台服务器换端口回包是否可达
    final r5 = await _binding(servers[1], codec, changePort: true);
    if (r5 != null) {
      return NatDetectionResult(
        type: NatType.restrictedCone,
        mappedAddress: r1,
      );
    }
    return NatDetectionResult(
      type: NatType.portRestrictedCone,
      mappedAddress: r1,
    );
  }

  /// 发送一次 Binding Request 并解析映射地址；失败返回 null。
  Future<String?> _binding(
    StunServer server,
    StunPacket codec, {
    bool changeIp = false,
    bool changePort = false,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription? sub;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<String?>();
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final mapped = codec.parseBindingResponse(datagram.data);
        if (mapped != null && !completer.isCompleted) {
          completer.complete(mapped);
        }
      });
      final request = codec.buildBindingRequest(
        changeIp: changeIp,
        changePort: changePort,
      );
      socket.send(request, InternetAddress(server.host), server.port);
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  int? _portOf(String address) {
    final idx = address.lastIndexOf(':');
    if (idx < 0) return null;
    return int.tryParse(address.substring(idx + 1));
  }
}
