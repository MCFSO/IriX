/*
 * CPU feature detection via CPUID. Compile-time portable (MSVC / GCC / Clang).
 */
#include "simd.h"
#include <stdio.h>   /* snprintf for caps_json */

#if defined(_MSC_VER)
#include <intrin.h>
#else
#include <cpuid.h>
#endif

static uint32_t g_caps = 0;

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__)

static uint32_t detect_caps(void) {
    uint32_t caps = 0;
#if defined(_MSC_VER)
    int info[4] = {0, 0, 0, 0};
    __cpuidex(info, 0, 0);
    const int max_leaf = info[0];
    if (max_leaf >= 1) {
        __cpuidex(info, 1, 0);
        const uint32_t ecx = (uint32_t)info[2];
        const uint32_t edx = (uint32_t)info[3];
        if (edx & (1u << 26)) caps |= XMC_CPU_SSE2;
        if (ecx & (1u << 9))  caps |= XMC_CPU_SSSE3;
        if (ecx & (1u << 20)) caps |= XMC_CPU_SSE42;
        if (ecx & (1u << 1))  caps |= XMC_CPU_PCLMULQDQ;
        if (ecx & (1u << 28)) caps |= XMC_CPU_AVX;
    }
    if (max_leaf >= 7) {
        __cpuidex(info, 7, 0);
        const uint32_t ebx = (uint32_t)info[1];
        if (ebx & (1u << 5))  caps |= XMC_CPU_AVX2;
        if (ebx & (1u << 16)) caps |= XMC_CPU_AVX512F;
        if (ebx & (1u << 8))  caps |= XMC_CPU_BMI2;
    }
#else
    unsigned int eax, ebx, ecx, edx;
    if (__get_cpuid_max(0, NULL) >= 1) {
        __cpuid(1, eax, ebx, ecx, edx);
        if (edx & (1u << 26)) caps |= XMC_CPU_SSE2;
        if (ecx & (1u << 9))  caps |= XMC_CPU_SSSE3;
        if (ecx & (1u << 20)) caps |= XMC_CPU_SSE42;
        if (ecx & (1u << 1))  caps |= XMC_CPU_PCLMULQDQ;
        if (ecx & (1u << 28)) caps |= XMC_CPU_AVX;
    }
    unsigned int max7 = __get_cpuid_max(0, NULL);
    if (max7 >= 7) {
        __cpuid_count(7, 0, eax, ebx, ecx, edx);
        if (ebx & (1u << 5))  caps |= XMC_CPU_AVX2;
        if (ebx & (1u << 16)) caps |= XMC_CPU_AVX512F;
        if (ebx & (1u << 8))  caps |= XMC_CPU_BMI2;
    }
#endif
    return caps;
}

#else  /* non-x86 (e.g. macOS arm64): no SIMD variants, all scalar */

static uint32_t detect_caps(void) {
    return 0;
}

#endif

uint32_t xmc_simd_caps(void) {
    if (g_caps == 0) {
        g_caps = detect_caps(); /* benign race: all writers store the same value */
    }
    return g_caps;
}

const char *xmc_simd_caps_json(void) {
    static char buf[256];
    static int built = 0;
    if (!built) {
        const uint32_t c = xmc_simd_caps();
        snprintf(buf, sizeof(buf),
                 "{\"sse2\":%s,\"ssse3\":%s,\"sse42\":%s,\"pclmulqdq\":%s,"
                 "\"avx\":%s,\"avx2\":%s,\"avx512f\":%s,\"bmi2\":%s}",
                 (c & XMC_CPU_SSE2) ? "true" : "false",
                 (c & XMC_CPU_SSSE3) ? "true" : "false",
                 (c & XMC_CPU_SSE42) ? "true" : "false",
                 (c & XMC_CPU_PCLMULQDQ) ? "true" : "false",
                 (c & XMC_CPU_AVX) ? "true" : "false",
                 (c & XMC_CPU_AVX2) ? "true" : "false",
                 (c & XMC_CPU_AVX512F) ? "true" : "false",
                 (c & XMC_CPU_BMI2) ? "true" : "false");
        built = 1;
    }
    return buf;
}
