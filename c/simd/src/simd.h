/*
 * xmc_simd - SIMD-accelerated primitives for IriX (X Minecraft Server Launcher)
 *
 * Multi-version hot paths with runtime CPUID dispatch:
 *   - base64 encode: scalar / SSE2 / AVX2
 *   - CRC32 IEEE (zip): slice-by-8 scalar / PCLMULQDQ hardware
 *   - CRC32C (Castagnoli): SSE4.2 crc32 instruction
 *
 * Design: compile every variant, detect CPU at runtime, use the best
 * variant the CPU supports, never run a path the CPU cannot execute.
 */
#ifndef XMC_SIMD_H
#define XMC_SIMD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define XMC_API __declspec(dllexport)
#else
#define XMC_API __attribute__((visibility("default")))
#endif

/* CPU feature flags (bitmask returned by xmc_simd_caps) */
#define XMC_CPU_SSE2       (1u << 0)
#define XMC_CPU_SSSE3      (1u << 1)
#define XMC_CPU_SSE42      (1u << 2)
#define XMC_CPU_PCLMULQDQ  (1u << 3)
#define XMC_CPU_AVX        (1u << 4)
#define XMC_CPU_AVX2       (1u << 5)
#define XMC_CPU_AVX512F    (1u << 6)
#define XMC_CPU_BMI2       (1u << 7)

/* --- CPU capability --- */

/* Detect CPU features once (thread-safe, cached). Returns bitmask. */
XMC_API uint32_t xmc_simd_caps(void);

/* JSON string like {"sse2":true,"avx2":true,...}. Static, do not free. */
XMC_API const char *xmc_simd_caps_json(void);

/* --- base64 (RFC 4648, with padding) --- */

/* Encode in_len bytes to out (caller must provide >= xmc_base64_encoded_len(in_len) bytes).
 * Returns characters written (always a multiple of 4). */
XMC_API size_t xmc_base64_encoded_len(size_t in_len);

/* Auto-dispatch entry point (used by the app). */
XMC_API size_t xmc_base64_encode(const uint8_t *in, size_t in_len, char *out);

/* Individual variants (exposed for benchmarking / explicit control). */
XMC_API size_t xmc_base64_encode_scalar(const uint8_t *in, size_t in_len, char *out);
XMC_API size_t xmc_base64_encode_sse2(const uint8_t *in, size_t in_len, char *out);
XMC_API size_t xmc_base64_encode_avx2(const uint8_t *in, size_t in_len, char *out);

/* --- base64 decode (RFC 4648, optional '=' padding) --- */

/* Upper bound of decoded bytes for in_len input chars (>= actual). */
XMC_API size_t xmc_base64_decoded_len(size_t in_len);

/* Decode in_len chars to out (caller must provide >= xmc_base64_decoded_len(in_len)).
 * Returns bytes written, or SIZE_MAX on invalid input (bad chars / bad length). */
XMC_API size_t xmc_base64_decode(const uint8_t *in, size_t in_len, uint8_t *out);

XMC_API size_t xmc_base64_decode_scalar(const uint8_t *in, size_t in_len, uint8_t *out);
XMC_API size_t xmc_base64_decode_ssse3(const uint8_t *in, size_t in_len, uint8_t *out);
XMC_API size_t xmc_base64_decode_avx2(const uint8_t *in, size_t in_len, uint8_t *out);

/* --- CRC32 IEEE (poly 0xEDB88320, zip/gzip compatible) --- */

XMC_API uint32_t xmc_crc32_ieee(const uint8_t *data, size_t len, uint32_t seed);

XMC_API uint32_t xmc_crc32_ieee_slice8(const uint8_t *data, size_t len, uint32_t seed);
XMC_API uint32_t xmc_crc32_ieee_pclmul(const uint8_t *data, size_t len, uint32_t seed);

/* --- CRC32C Castagnoli (poly 0x82F63B78, SSE4.2 hardware instruction) --- */

XMC_API uint32_t xmc_crc32c(const uint8_t *data, size_t len, uint32_t seed);

#ifdef __cplusplus
}
#endif

#endif /* XMC_SIMD_H */
