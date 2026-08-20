#!/usr/bin/env bash
# Build xmc_simd shared library for Linux (x86-64).
# Output: build/libxmc_simd.so  (+ build/bench)
# Requires: gcc/clang with x86-64 SIMD support.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-gcc}"
OUT=build
mkdir -p "$OUT"

# Each SIMD variant is compiled separately so the shared object itself never
# requires AVX2 etc.; runtime CPUID dispatch picks the right path.
$CC -O2 -fPIC -c src/cpuid.c              -o "$OUT/cpuid.o"
$CC -O2 -fPIC -c src/base64_scalar.c      -o "$OUT/base64_scalar.o"
$CC -O2 -fPIC -mssse3 -c src/base64_sse2.c -o "$OUT/base64_sse2.o"
$CC -O2 -fPIC -mavx2 -c src/base64_avx2.c  -o "$OUT/base64_avx2.o"
$CC -O2 -fPIC -c src/base64_decode_scalar.c -o "$OUT/base64_decode_scalar.o"
$CC -O2 -fPIC -mssse3 -c src/base64_decode_ssse3.c -o "$OUT/base64_decode_ssse3.o"
$CC -O2 -fPIC -mavx2 -c src/base64_decode_avx2.c   -o "$OUT/base64_decode_avx2.o"
$CC -O2 -fPIC -mssse3 -mpclmul -c src/crc32.c -o "$OUT/crc32.o"
$CC -O2 -fPIC -msse4.2 -c src/crc32c.c     -o "$OUT/crc32c.o"
$CC -O2 -fPIC -c src/simd_dll.c            -o "$OUT/simd_dll.o"

$CC -shared -o "$OUT/libxmc_simd.so" "$OUT"/cpuid.o "$OUT"/base64_scalar.o \
    "$OUT"/base64_sse2.o "$OUT"/base64_avx2.o "$OUT"/base64_decode_scalar.o \
    "$OUT"/base64_decode_ssse3.o "$OUT"/base64_decode_avx2.o \
    "$OUT"/crc32.o "$OUT"/crc32c.o "$OUT"/simd_dll.o

# benchmark (optional, links the same objects)
$CC -O2 -c src/bench.c -o "$OUT/bench.o"
$CC -o "$OUT/bench" "$OUT"/cpuid.o "$OUT"/base64_scalar.o "$OUT"/base64_sse2.o \
    "$OUT"/base64_avx2.o "$OUT"/base64_decode_scalar.o "$OUT"/base64_decode_ssse3.o \
    "$OUT"/base64_decode_avx2.o "$OUT"/crc32.o "$OUT"/crc32c.o "$OUT"/simd_dll.o \
    "$OUT"/bench.o -lm

echo "OK: $OUT/libxmc_simd.so  $OUT/bench"
