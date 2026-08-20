# xmc_simd — SIMD-accelerated primitives (C, MSVC)

多版本热路径 + CPUID 运行时分发的 C 库，编译为 `xmc_simd.dll`，
供 IriX 通过 Dart FFI 调用。设计原则：**CPU 支持什么指令集就用什么，
不支持的回退到低版本，绝不执行 CPU 无法运行的路径**。

## 功能

| 函数 | 说明 | 变体 |
|---|---|---|
| `xmc_base64_encode` | RFC 4648 base64 编码（带 padding） | scalar / SSSE3 / AVX2 |
| `xmc_base64_decode` | RFC 4648 base64 解码（含 padding 与非法输入检测） | scalar / SSSE3 / AVX2 |
| `xmc_crc32_ieee` | CRC32 IEEE（zip/gzip 兼容） | slice-by-8 / PCLMULQDQ |
| `xmc_crc32c` | CRC32C Castagnoli（iSCSI/Redis） | SSE4.2 硬件指令 |
| `xmc_simd_caps` / `xmc_simd_caps_json` | CPU 特性检测（位掩码 / JSON） | — |

`xmc_base64_encode` / `xmc_base64_decode` / `xmc_crc32_ieee` 为自动分发
入口：首次调用时检测 CPUID，之后固定走最快路径（AVX2 → SSSE3 →
scalar；PCLMULQDQ → slice8）。其余 `*_sse2` / `*_avx2` / `*_scalar` /
`*_slice8` / `*_pclmul` 变体单独导出，供基准测试与显式控制。

## 性能（Intel Core Ultra 5 125H, MSVC /O2 /GL）

| 函数 | 标量 | SIMD | 加速 |
|---|---|---|---|
| base64 编码 | 2.8 GB/s | AVX2 6.1 GB/s | 2.2× |
| base64 解码 | 2.3 GB/s | AVX2 5.3 GB/s | 2.3× |
| CRC32 IEEE | 2.5 GB/s | PCLMULQDQ 17 GB/s | 7× |
| CRC32C | — | SSE4.2 7 GB/s | — |

## 编译

| 平台 | 脚本 | 产物 |
|---|---|---|
| Windows | `build.bat`（MSVC，自动定位 vcvars64 / 跳过已激活环境） | `build/xmc_simd.dll` + `build/bench.exe` |
| Linux | `build.sh`（gcc/clang，x86-64） | `build/libxmc_simd.so` + `build/bench` |
| macOS | `build_macos.sh`（x86_64 SIMD + arm64 标量，lipo 通用库） | `build/libxmc_simd.dylib` |

CI（`.github/workflows/build-and-test.yml` / `package.yml`）已集成三平台
构建与复制；`build_rust.bat` / `build_rust.sh` 会在 Rust 构建后一并构建
SIMD 库并复制到平台目录。

编译要点：

- 每个 SIMD 变体**单独 .c 文件**编译（AVX2 文件加 `/arch:AVX2` /
  `-mavx2`，CRC32 加 `-mpclmul`，CRC32C 加 `-msse4.2`），避免整个库
  被标记为需要 AVX2；
- 运行时通过 `xmc_simd_caps()`（CPUID leaf 1/7）分发，任何 CPU
  都能安全运行（不支持的路径永远不会被调用）；
- macOS arm64 切片只编译标量变体（`cpuid.c` 非 x86 返回 0，
  `crc32.c` 回退 slice8），由 `build_macos.sh` lipo 合并为通用库。

## IriX 接入

- **Dart FFI 封装**：`lib/services/simd_ffi.dart`（`SimdNative` 单例，
  库缺失自动回退；`simdBase64Decode` / `simdCrc32Ieee` / `simdCrc32c`）
- **HTTP 响应解码**：`lib/services/http_ffi.dart` 的响应体 base64 解码
  优先走 SIMD（AVX2 ~5 GB/s，约为 `dart:convert` 的 2.3 倍），
  库不可用或输入非法时回退 `dart:convert`
- **测试**：`test/simd_ffi_test.dart`（需 DLL 在 `windows/runner/` 或
  项目根）

## 实现要点

- **base64 编码 AVX2**：每 24 字节 → 32 字符。pshufb 把每组 3 字节
  反转成大端布局 → 4 次 32 位移位提取 6 位索引 → 无分支比较/掩码
  映射到 ASCII 表（`+`/`/`/大小写三段式修正）。尾部用标量补齐。
- **base64 解码 AVX2**：每 32 字符 → 24 字节。无分支字符→索引映射
  （含 `>= 'A'`/`>= '0'` 分段修正）+ movemask 非法字符检测 +
  逐字节提取打包为 3 字节组 + permutevar8x32 跨通道合并。
  尾部（含 `=` padding）回退标量（含未用位校验）。
- **CRC32 PCLMULQDQ**：4 状态并行折叠，直接移植 zlib-ng 2.2.4
  （Intel 白皮书算法）：`fold_1..4` 交叉无进位乘 + `partial_fold`
  pshufb 尾部 + k1/k5/k7 两阶段归约。反射域运算，无需字节交换。
  长度 < 16 回退 slice-by-8。
- **CRC32C**：`_mm_crc32_u64/u32/u8` 硬件指令，天然正确。

## FFI 签名（Dart 侧）

```dart
// xmc_simd.dll
int xmc_base64_encode(Pointer<Uint8> in, int inLen, Pointer<Uint8> out);   // 返回输出字符数
int xmc_base64_decode(Pointer<Uint8> in, int inLen, Pointer<Uint8> out);   // 返回字节数；-1 非法
int xmc_crc32_ieee(Pointer<Uint8> data, int len, int seed);
int xmc_crc32c(Pointer<Uint8> data, int len, int seed);
Pointer<Utf8> xmc_simd_caps_json();
```

`out` 缓冲区：编码 `((inLen + 2) / 3) * 4`；解码 `(inLen / 4) * 3 + 3`。

## 回归工具

- `src/bench.c` — 正确性（与标量全长度对比 + 标准测试向量）+ 吞吐
- `src/crc_debug.c` / `src/b64_debug.c` — 逐长度扫描定位差异（调试用）

## 许可说明

CRC32 PCLMULQDQ 实现结构来自 zlib-ng（zlib license），
见 `src/crc32.c` 头部注释。
