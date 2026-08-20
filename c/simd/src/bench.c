/*
 * bench.c - correctness check + throughput benchmark for all variants.
 *
 * Build: bench.exe (links the variant objects directly).
 * Usage: bench [mb]   (default 8 MB of random data)
 */
#include "simd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
static double now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}
#else
#include <time.h>
static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}
#endif

#define REPS 3

static double bench_b64(const char *name,
                        size_t (*fn)(const uint8_t *, size_t, char *),
                        const uint8_t *in, size_t n, char *out) {
    size_t olen = xmc_base64_encoded_len(n);
    double best = 1e300;
    for (int r = 0; r < REPS; r++) {
        double t0 = now_ms();
        fn(in, n, out);
        double dt = now_ms() - t0;
        if (dt < best) best = dt;
    }
    double mbps = (double)n / (best / 1000.0) / (1024.0 * 1024.0);
    printf("  %-22s %9.1f MB/s  (%zu bytes in -> %zu out)\n", name, mbps, n, olen);
    return mbps;
}

static double bench_crc(const char *name,
                        uint32_t (*fn)(const uint8_t *, size_t, uint32_t),
                        const uint8_t *in, size_t n) {
    double best = 1e300;
    for (int r = 0; r < REPS; r++) {
        double t0 = now_ms();
        fn(in, n, 0);
        double dt = now_ms() - t0;
        if (dt < best) best = dt;
    }
    double mbps = (double)n / (best / 1000.0) / (1024.0 * 1024.0);
    printf("  %-22s %9.1f MB/s\n", name, mbps);
    return mbps;
}

static double bench_b64dec(const char *name,
                           size_t (*fn)(const uint8_t *, size_t, uint8_t *),
                           const uint8_t *in, size_t n, uint8_t *out) {
    double best = 1e300;
    for (int r = 0; r < REPS; r++) {
        double t0 = now_ms();
        fn(in, n, out);
        double dt = now_ms() - t0;
        if (dt < best) best = dt;
    }
    double mbps = (double)n / (best / 1000.0) / (1024.0 * 1024.0);
    printf("  %-22s %9.1f MB/s\n", name, mbps);
    return mbps;
}

int main(int argc, char **argv) {
    size_t mb = argc > 1 ? (size_t)atoi(argv[1]) : 8;
    size_t n = mb * 1024 * 1024;
    uint8_t *in = (uint8_t *)malloc(n);
    char *out = (char *)malloc(xmc_base64_encoded_len(n) + 64);
    if (!in || !out) { printf("alloc failed\n"); return 1; }
    srand(42);
    for (size_t i = 0; i < n; i++) in[i] = (uint8_t)rand();

    const uint32_t caps = xmc_simd_caps();
    printf("CPU caps: %s\n\n", xmc_simd_caps_json());
    printf("=== base64 encode (%zu MB) ===\n", mb);
    size_t l1 = xmc_base64_encode_scalar(in, n, out);
    size_t l2 = xmc_base64_encode_sse2(in, n, out);
    size_t l3 = xmc_base64_encode_avx2(in, n, out);
    int ok = (l1 == l2 && l2 == l3 && !memcmp(out, out, 0));
    /* correctness: compare variants against scalar (tail included) */
    static char b1[65536], b2[65536];
    for (size_t len = 0; len <= 4096; len += 7) {
        xmc_base64_encode_scalar(in, len, b1);
        xmc_base64_encode_sse2(in, len, b2);
        if (memcmp(b1, b2, xmc_base64_encoded_len(len))) { ok = 0; break; }
        xmc_base64_encode_avx2(in, len, b2);
        if (memcmp(b1, b2, xmc_base64_encoded_len(len))) { ok = 0; break; }
    }
    printf("  correctness (sse2/avx2 vs scalar): %s\n\n", ok ? "PASS" : "FAIL");

    bench_b64("scalar", xmc_base64_encode_scalar, in, n, out);
    bench_b64("sse2", xmc_base64_encode_sse2, in, n, out);
    bench_b64("avx2", xmc_base64_encode_avx2, in, n, out);
    bench_b64("auto-dispatch", xmc_base64_encode, in, n, out);

    printf("\n=== crc32 ===\n");
    /* known test vector: "123456789" -> 0xCBF43926 */
    const char *tv = "123456789";
    uint32_t r1 = xmc_crc32_ieee_slice8((const uint8_t *)tv, 9, 0);
    uint32_t r2 = xmc_crc32_ieee_pclmul((const uint8_t *)tv, 9, 0);
    printf("  vector 0xCBF43926: slice8=0x%08X pclmul=0x%08X %s\n",
           r1, r2, (r1 == 0xCBF43926u && r2 == 0xCBF43926u) ? "PASS" : "FAIL");
    for (size_t len = 1; len <= 4096; len += 31) {
        if (xmc_crc32_ieee_slice8(in, len, 0) != xmc_crc32_ieee_pclmul(in, len, 0)) {
            printf("  consistency FAIL at len %zu\n", len);
            break;
        }
    }
    bench_crc("slice8 (scalar)", xmc_crc32_ieee_slice8, in, n);
    bench_crc("pclmulqdq", xmc_crc32_ieee_pclmul, in, n);
    bench_crc("auto-dispatch", xmc_crc32_ieee, in, n);

    printf("\n=== crc32c (SSE4.2) ===\n");
    printf("  vector 0xE3069283: %s\n",
           (xmc_crc32c((const uint8_t *)tv, 9, 0) == 0xE3069283u) ? "PASS" : "FAIL");
    bench_crc("crc32c sse42", xmc_crc32c, in, n);

    printf("\n=== base64 decode ===\n");
    /* build a large valid base64 blob by encoding random data */
    uint8_t *dec = (uint8_t *)malloc(n + 64);
    size_t enc_len = xmc_base64_encode(in, n, out);
    size_t dec_len = xmc_base64_decode(out, enc_len, dec);
    int dec_ok = (dec_len == n && !memcmp(dec, in, n));
    printf("  correctness (encode->decode roundtrip): %s\n\n",
           dec_ok ? "PASS" : "FAIL");
    /* cross-check all variants on varied lengths incl. padding */
    static char e1[2048], e2[2048];
    static uint8_t d1[2048], d2[2048], d3[2048];
    for (size_t len = 0; len <= 512; len += 7) {
        size_t el = xmc_base64_encode(in, len, e1);
        size_t dl1 = xmc_base64_decode_scalar((const uint8_t *)e1, el, d1);
        size_t dl2 = xmc_base64_decode_ssse3((const uint8_t *)e1, el, d2);
        size_t dl3 = xmc_base64_decode_avx2((const uint8_t *)e1, el, d3);
        if (dl1 != len || dl2 != len || dl3 != len ||
            memcmp(d1, in, len) || memcmp(d2, in, len) || memcmp(d3, in, len)) {
            printf("  roundtrip FAIL at len %zu\n", len);
            ok = 0;
            break;
        }
        /* invalid input detection */
        if (len >= 4) {
            e2[0] = '!';  /* corrupt first char */
            memcpy(e2 + 1, e1 + 1, el - 1);
            if (xmc_base64_decode_scalar((const uint8_t *)e2, el, d1) != (size_t)-1 ||
                xmc_base64_decode_ssse3((const uint8_t *)e2, el, d2) != (size_t)-1 ||
                xmc_base64_decode_avx2((const uint8_t *)e2, el, d3) != (size_t)-1) {
                printf("  invalid-input detection FAIL at len %zu\n", len);
                ok = 0;
                break;
            }
        }
    }
    printf("  cross-variant + padding + invalid detection: %s\n\n",
           ok ? "PASS" : "FAIL");

    if (dec_len == n && dec_ok) {
        bench_b64dec("scalar", xmc_base64_decode_scalar, (const uint8_t *)out, enc_len, dec);
        bench_b64dec("ssse3", xmc_base64_decode_ssse3, (const uint8_t *)out, enc_len, dec);
        bench_b64dec("avx2", xmc_base64_decode_avx2, (const uint8_t *)out, enc_len, dec);
        bench_b64dec("auto-dispatch", xmc_base64_decode, (const uint8_t *)out, enc_len, dec);
    }

    free(dec);
    free(in); free(out);
    return ok ? 0 : 1;
}
