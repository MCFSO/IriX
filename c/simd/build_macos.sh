#!/usr/bin/env bash
# Build xmc_simd universal dylib for macOS (x86_64 + arm64 -> lipo).
# Output: build/libxmc_simd.dylib
# x86_64 slice uses the SIMD variants; arm64 slice is scalar-only
# (no PCLMULQDQ/AVX2 on Apple Silicon; runtime dispatch falls back).
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-clang}"
OUT=build
mkdir -p "$OUT" "$OUT/x86_64" "$OUT/arm64"

common=(-O2 -fPIC -Wall)

# ---- x86_64 slice (all variants) ----
$CC "${common[@]}" -arch x86_64 -c src/cpuid.c                  -o "$OUT/x86_64/cpuid.o"
$CC "${common[@]}" -arch x86_64 -c src/base64_scalar.c          -o "$OUT/x86_64/base64_scalar.o"
$CC "${common[@]}" -arch x86_64 -mssse3 -c src/base64_sse2.c    -o "$OUT/x86_64/base64_sse2.o"
$CC "${common[@]}" -arch x86_64 -mavx2 -c src/base64_avx2.c     -o "$OUT/x86_64/base64_avx2.o"
$CC "${common[@]}" -arch x86_64 -c src/base64_decode_scalar.c   -o "$OUT/x86_64/base64_decode_scalar.o"
$CC "${common[@]}" -arch x86_64 -mssse3 -c src/base64_decode_ssse3.c -o "$OUT/x86_64/base64_decode_ssse3.o"
$CC "${common[@]}" -arch x86_64 -mavx2 -c src/base64_decode_avx2.c   -o "$OUT/x86_64/base64_decode_avx2.o"
$CC "${common[@]}" -arch x86_64 -mpclmul -c src/crc32.c          -o "$OUT/x86_64/crc32.o"
$CC "${common[@]}" -arch x86_64 -msse4.2 -c src/crc32c.c         -o "$OUT/x86_64/crc32c.o"
$CC "${common[@]}" -arch x86_64 -c src/simd_dll.c               -o "$OUT/x86_64/simd_dll.o"
$CC -dynamiclib -arch x86_64 -o "$OUT/x86_64/libxmc_simd.dylib" \
    "$OUT"/x86_64/*.o -Wl,-install_name,@rpath/libxmc_simd.dylib

# ---- arm64 slice (scalar-only: cpuid.c guards non-x86, crc32.c falls back) ----
$CC "${common[@]}" -arch arm64 -c src/cpuid.c                  -o "$OUT/arm64/cpuid.o"
$CC "${common[@]}" -arch arm64 -c src/base64_scalar.c          -o "$OUT/arm64/base64_scalar.o"
$CC "${common[@]}" -arch arm64 -c src/base64_decode_scalar.c   -o "$OUT/arm64/base64_decode_scalar.o"
$CC "${common[@]}" -arch arm64 -c src/crc32.c                  -o "$OUT/arm64/crc32.o"
$CC "${common[@]}" -arch arm64 -c src/crc32c.c                 -o "$OUT/arm64/crc32c.o"
$CC "${common[@]}" -arch arm64 -c src/simd_dll.c               -o "$OUT/arm64/simd_dll.o"
$CC -dynamiclib -arch arm64 -o "$OUT/arm64/libxmc_simd.dylib" \
    "$OUT"/arm64/*.o -Wl,-install_name,@rpath/libxmc_simd.dylib

# ---- universal ----
lipo -create "$OUT/x86_64/libxmc_simd.dylib" "$OUT/arm64/libxmc_simd.dylib" \
    -output "$OUT/libxmc_simd.dylib"

echo "OK: $OUT/libxmc_simd.dylib"
