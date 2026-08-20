/*
 * xmc_simd.dll - runtime dispatch entry points.
 *
 * Auto-selects the fastest variant the CPU supports (CPUID at first use).
 * Never executes a SIMD path the CPU cannot run.
 */
#include "simd.h"

/* ------------------------------ base64 ------------------------------ */

size_t xmc_base64_encode(const uint8_t *in, size_t in_len, char *out) {
#if defined(__x86_64__) || defined(_M_X64)
    const uint32_t caps = xmc_simd_caps();
    if (caps & XMC_CPU_AVX2)   return xmc_base64_encode_avx2(in, in_len, out);
    if (caps & XMC_CPU_SSSE3)  return xmc_base64_encode_sse2(in, in_len, out);
#endif
    return xmc_base64_encode_scalar(in, in_len, out);
}

size_t xmc_base64_decode(const uint8_t *in, size_t in_len, uint8_t *out) {
#if defined(__x86_64__) || defined(_M_X64)
    const uint32_t caps = xmc_simd_caps();
    if (caps & XMC_CPU_AVX2)   return xmc_base64_decode_avx2(in, in_len, out);
    if (caps & XMC_CPU_SSSE3)  return xmc_base64_decode_ssse3(in, in_len, out);
#endif
    return xmc_base64_decode_scalar(in, in_len, out);
}

/* ------------------------------- crc32 ------------------------------ */

uint32_t xmc_crc32_ieee(const uint8_t *data, size_t len, uint32_t seed) {
#if defined(__x86_64__) || defined(_M_X64)
    const uint32_t caps = xmc_simd_caps();
    if (caps & XMC_CPU_PCLMULQDQ) return xmc_crc32_ieee_pclmul(data, len, seed);
#endif
    return xmc_crc32_ieee_slice8(data, len, seed);
}

/* crc32c uses the SSE4.2 instruction; without SSE4.2 fall back to IEEE
 * (callers needing exact CRC32C on ancient CPUs should use their own). */
uint32_t xmc_crc32c_dispatch(const uint8_t *data, size_t len, uint32_t seed) {
#if defined(__x86_64__) || defined(_M_X64)
    if (xmc_simd_caps() & XMC_CPU_SSE42) return xmc_crc32c(data, len, seed);
#endif
    return xmc_crc32_ieee_slice8(data, len, seed);
}
