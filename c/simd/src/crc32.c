/*
 * CRC32 IEEE (poly 0xEDB88320, zip/gzip compatible).
 *
 * - slice-by-8 lookup-table variant (scalar, portable)
 * - PCLMULQDQ 4-state parallel folding (x86-64 with PCLMULQDQ)
 *
 * The PCLMULQDQ variant is a direct port of the single-block path of
 * zlib-ng arch/x86/crc32_pclmulqdq_tpl.h (Intel white paper "Fast CRC
 * Computation for Generic Polynomials Using PCLMULQDQ"): 4 parallel
 * 128-bit fold states with FOLD4 constants, K12 state merge, pshufb
 * tail handling and two-stage Barrett reduction. Reflected-domain, so
 * no byte swapping is performed on the data.
 */
#include "simd.h"
#include <string.h>

/* ------------------------------------------------------------------ */
/* shared tables                                                       */
/* ------------------------------------------------------------------ */

static uint32_t g_tab[8][256];
static int g_tab_ready = 0;

static void crc32_init_tables(void) {
    if (g_tab_ready) return;
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xEDB88320u & (uint32_t)-(int32_t)(c & 1));
        g_tab[0][i] = c;
    }
    for (uint32_t i = 0; i < 256; i++)
        for (int t = 1; t < 8; t++)
            g_tab[t][i] = (g_tab[t - 1][i] >> 8) ^ g_tab[0][g_tab[t - 1][i] & 0xFF];
    g_tab_ready = 1;
}

static uint32_t crc32_tail_bytes(const uint8_t *p, size_t len, uint32_t crc) {
    for (size_t i = 0; i < len; i++)
        crc = (crc >> 8) ^ g_tab[0][(crc ^ p[i]) & 0xFF];
    return crc;
}

/* ------------------------------------------------------------------ */
/* slice-by-8 (scalar)                                                 */
/* ------------------------------------------------------------------ */

uint32_t xmc_crc32_ieee_slice8(const uint8_t *data, size_t len, uint32_t seed) {
    crc32_init_tables();
    uint32_t crc = seed ^ 0xFFFFFFFFu;
    while (len >= 8) {
        uint32_t lo, hi;
        memcpy(&lo, data, 4);
        memcpy(&hi, data + 4, 4);
        lo ^= crc;
        crc = g_tab[7][lo & 0xFF] ^ g_tab[6][(lo >> 8) & 0xFF] ^
              g_tab[5][(lo >> 16) & 0xFF] ^ g_tab[4][lo >> 24] ^
              g_tab[3][hi & 0xFF] ^ g_tab[2][(hi >> 8) & 0xFF] ^
              g_tab[1][(hi >> 16) & 0xFF] ^ g_tab[0][hi >> 24];
        data += 8; len -= 8;
    }
    crc = crc32_tail_bytes(data, len, crc);
    return crc ^ 0xFFFFFFFFu;
}

/* ------------------------------------------------------------------ */
/* PCLMULQDQ 4-state folding - direct port of zlib-ng 2.2.4
 * arch/x86/crc32_pclmulqdq_tpl.h + crc32_fold_pclmulqdq_tpl.h
 * (Intel white paper "Fast CRC Computation for Generic Polynomials
 *  Using PCLMULQDQ"). Reflected-domain; no byte swapping.            */
/* ------------------------------------------------------------------ */

#if defined(__x86_64__) || defined(_M_X64)

#include <wmmintrin.h>
#include <tmmintrin.h>   /* pshufb */

/* pshufb shift table for partial_fold (zlib-ng, shl patterns for len 1..15) */
static const unsigned pshufb_shf_table[60] = {
    0x84838281, 0x88878685, 0x8c8b8a89, 0x008f8e8d, /* shl 15 */
    0x85848382, 0x89888786, 0x8d8c8b8a, 0x01008f8e, /* shl 14 */
    0x86858483, 0x8a898887, 0x8e8d8c8b, 0x0201008f, /* shl 13 */
    0x87868584, 0x8b8a8988, 0x8f8e8d8c, 0x03020100, /* shl 12 */
    0x88878685, 0x8c8b8a89, 0x008f8e8d, 0x04030201, /* shl 11 */
    0x89888786, 0x8d8c8b8a, 0x01008f8e, 0x05040302, /* shl 10 */
    0x8a898887, 0x8e8d8c8b, 0x0201008f, 0x06050403, /* shl  9 */
    0x8b8a8988, 0x8f8e8d8c, 0x03020100, 0x07060504, /* shl  8 */
    0x8c8b8a89, 0x008f8e8d, 0x04030201, 0x08070605, /* shl  7 */
    0x8d8c8b8a, 0x01008f8e, 0x05040302, 0x09080706, /* shl  6 */
    0x8e8d8c8b, 0x0201008f, 0x06050403, 0x0a090807, /* shl  5 */
    0x8f8e8d8c, 0x03020100, 0x07060504, 0x0b0a0908, /* shl  4 */
    0x008f8e8d, 0x04030201, 0x08070605, 0x0c0b0a09, /* shl  3 */
    0x01008f8e, 0x05040302, 0x09080706, 0x0d0c0b0a, /* shl  2 */
    0x0201008f, 0x06050403, 0x0a090807, 0x0e0d0c0b  /* shl  1 */
};

/* final reduction constants (zlib-ng crc_k / crc_mask) */
static const unsigned crc_k[] = {
    0xccaa009e, 0x00000000, /* rk1 */
    0x751997d0, 0x00000001, /* rk2 */
    0xccaa009e, 0x00000000, /* rk5 */
    0x63cd6124, 0x00000001, /* rk6 */
    0xf7011640, 0x00000001, /* rk7 */
    0xdb710640, 0x00000001  /* rk8 */
};
static const unsigned crc_mask[4]  = {0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0x00000000};
static const unsigned crc_mask2[4] = {0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};

static __m128i fold16_x(__m128i v, __m128i k) {
    return _mm_xor_si128(_mm_clmulepi64_si128(v, k, 0x01),
                         _mm_clmulepi64_si128(v, k, 0x10));
}

/* fold_1 from zlib-ng 2.2.4: c0=old c1, c1=old c2, c2=old c3, c3=fold(old c0) */
static void fold_1r(__m128i *c0, __m128i *c1, __m128i *c2, __m128i *c3) {
    const __m128i f4 = _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596);
    __m128i old0 = *c0, t3 = *c3;
    __m128i res = _mm_xor_si128(_mm_clmulepi64_si128(old0, f4, 0x01),
                                _mm_clmulepi64_si128(old0, f4, 0x10));
    *c0 = *c1; *c1 = *c2; *c2 = t3; *c3 = res;
}

static void fold_4(__m128i *c0, __m128i *c1, __m128i *c2, __m128i *c3) {
    const __m128i f4 = _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596);
    *c0 = fold16_x(*c0, f4);
    *c1 = fold16_x(*c1, f4);
    *c2 = fold16_x(*c2, f4);
    *c3 = fold16_x(*c3, f4);
}

/* partial_fold from zlib-ng 2.2.4 */
static void partial_fold(size_t len, __m128i *c0, __m128i *c1, __m128i *c2, __m128i *c3,
                         __m128i *part) {
    const __m128i f4 = _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596);
    const __m128i mask3 = _mm_set1_epi32((int32_t)0x80808080);
    __m128i shl = _mm_load_si128((const __m128i *)(pshufb_shf_table + 4 * (len - 1)));
    __m128i shr = _mm_xor_si128(shl, mask3);

    __m128i a0_0 = _mm_shuffle_epi8(*c0, shl);
    *c0 = _mm_shuffle_epi8(*c0, shr);
    __m128i t1 = _mm_shuffle_epi8(*c1, shl);
    *c0 = _mm_or_si128(*c0, t1);
    *c1 = _mm_shuffle_epi8(*c1, shr);
    __m128i t2 = _mm_shuffle_epi8(*c2, shl);
    *c1 = _mm_or_si128(*c1, t2);
    *c2 = _mm_shuffle_epi8(*c2, shr);
    __m128i t3 = _mm_shuffle_epi8(*c3, shl);
    *c2 = _mm_or_si128(*c2, t3);
    *c3 = _mm_shuffle_epi8(*c3, shr);
    *part = _mm_shuffle_epi8(*part, shl);
    *c3 = _mm_or_si128(*c3, *part);

    *c3 = _mm_xor_si128(*c3, _mm_clmulepi64_si128(a0_0, f4, 0x01));
    *c3 = _mm_xor_si128(*c3, _mm_clmulepi64_si128(a0_0, f4, 0x10));
}

/* final reduction from zlib-ng 2.2.4 CRC32_FOLD_FINAL */
static uint32_t fold_final(__m128i c0, __m128i c1, __m128i c2, __m128i c3) {
    __m128i x_tmp0, x_tmp1, x_tmp2, crc_fold;

    crc_fold = _mm_load_si128((const __m128i *)crc_k);              /* k1 */
    x_tmp0 = _mm_clmulepi64_si128(c0, crc_fold, 0x10);
    c0 = _mm_clmulepi64_si128(c0, crc_fold, 0x01);
    c1 = _mm_xor_si128(c1, x_tmp0);
    c1 = _mm_xor_si128(c1, c0);
    x_tmp1 = _mm_clmulepi64_si128(c1, crc_fold, 0x10);
    c1 = _mm_clmulepi64_si128(c1, crc_fold, 0x01);
    c2 = _mm_xor_si128(c2, x_tmp1);
    c2 = _mm_xor_si128(c2, c1);
    x_tmp2 = _mm_clmulepi64_si128(c2, crc_fold, 0x10);
    c2 = _mm_clmulepi64_si128(c2, crc_fold, 0x01);
    c3 = _mm_xor_si128(c3, x_tmp2);
    c3 = _mm_xor_si128(c3, c2);

    crc_fold = _mm_load_si128((const __m128i *)(crc_k + 4));        /* k5 */
    c0 = c3;
    c3 = _mm_clmulepi64_si128(c3, crc_fold, 0);
    c0 = _mm_srli_si128(c0, 8);
    c3 = _mm_xor_si128(c3, c0);
    c0 = c3;
    c3 = _mm_slli_si128(c3, 4);
    c3 = _mm_clmulepi64_si128(c3, crc_fold, 0x10);
    c3 = _mm_xor_si128(c3, c0);
    c3 = _mm_and_si128(c3, _mm_load_si128((const __m128i *)crc_mask2));

    crc_fold = _mm_load_si128((const __m128i *)(crc_k + 8));        /* k7 */
    c1 = c3;
    c2 = c3;
    c3 = _mm_clmulepi64_si128(c3, crc_fold, 0);
    c3 = _mm_xor_si128(c3, c2);
    c3 = _mm_and_si128(c3, _mm_load_si128((const __m128i *)crc_mask));
    c2 = c3;
    c3 = _mm_clmulepi64_si128(c3, crc_fold, 0x10);
    c3 = _mm_xor_si128(c3, c2);
    c3 = _mm_xor_si128(c3, c1);

    return ~((uint32_t)_mm_extract_epi32(c3, 2));
}

uint32_t xmc_crc32_ieee_pclmul(const uint8_t *data, size_t len, uint32_t seed) {
    if (len < 16)
        return xmc_crc32_ieee_slice8(data, len, seed);

    __m128i c0 = _mm_cvtsi32_si128(0x9db42487);   /* fold reset state */
    __m128i c1 = _mm_setzero_si128();
    __m128i c2 = _mm_setzero_si128();
    __m128i c3 = _mm_setzero_si128();
    __m128i init = _mm_cvtsi32_si128((int)seed);
    int first = (seed != 0);

    while (len >= 64) {
        len -= 64;
        __m128i t0 = _mm_loadu_si128((const __m128i *)data);
        __m128i t1 = _mm_loadu_si128((const __m128i *)data + 1);
        __m128i t2 = _mm_loadu_si128((const __m128i *)data + 2);
        __m128i t3 = _mm_loadu_si128((const __m128i *)data + 3);
        data += 64;
        if (first) { t0 = _mm_xor_si128(t0, init); first = 0; }
        fold_4(&c0, &c1, &c2, &c3);
        c0 = _mm_xor_si128(c0, t0);
        c1 = _mm_xor_si128(c1, t1);
        c2 = _mm_xor_si128(c2, t2);
        c3 = _mm_xor_si128(c3, t3);
    }
    if (len >= 48) {
        len -= 48;
        __m128i t0 = _mm_loadu_si128((const __m128i *)data);
        __m128i t1 = _mm_loadu_si128((const __m128i *)data + 1);
        __m128i t2 = _mm_loadu_si128((const __m128i *)data + 2);
        data += 48;
        if (first) { t0 = _mm_xor_si128(t0, init); first = 0; }
        /* fold_3: c0=old c3, c1=fold(old c0), c2=fold(old c1), c3=fold(old c2) */
        __m128i f4 = _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596);
        __m128i old0 = c0, old1 = c1, old2 = c2;
        c0 = c3;
        c1 = _mm_xor_si128(fold16_x(old0, f4), t0);
        c2 = _mm_xor_si128(fold16_x(old1, f4), t1);
        c3 = _mm_xor_si128(fold16_x(old2, f4), t2);
    } else if (len >= 32) {
        len -= 32;
        __m128i t0 = _mm_loadu_si128((const __m128i *)data);
        __m128i t1 = _mm_loadu_si128((const __m128i *)data + 1);
        data += 32;
        if (first) { t0 = _mm_xor_si128(t0, init); first = 0; }
        __m128i old0 = c0, old1 = c1, old3 = c3;
        c0 = c2; c1 = old3;
        c2 = fold16_x(old0, _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596));
        c3 = fold16_x(old1, _mm_set_epi32(0x00000001, 0x54442bd4, 0x00000001, 0xc6e41596));
        c2 = _mm_xor_si128(c2, t0);
        c3 = _mm_xor_si128(c3, t1);
    } else if (len >= 16) {
        len -= 16;
        __m128i t0 = _mm_loadu_si128((const __m128i *)data);
        data += 16;
        if (first) { t0 = _mm_xor_si128(t0, init); first = 0; }
        fold_1r(&c0, &c1, &c2, &c3);
        c3 = _mm_xor_si128(c3, t0);
    }
    if (len) {
        __m128i part = _mm_setzero_si128();
        memcpy(&part, data, len);
        partial_fold(len, &c0, &c1, &c2, &c3, &part);
    }
    return fold_final(c0, c1, c2, c3);
}

#else

uint32_t xmc_crc32_ieee_pclmul(const uint8_t *data, size_t len, uint32_t seed) {
    return xmc_crc32_ieee_slice8(data, len, seed);
}

#endif
