/*
 * base64 encode - AVX2 variant.
 *
 * Same algorithm as the SSE2 variant, but 256-bit: two 128-bit lanes,
 * each processing 12 input bytes -> 16 output chars, so 24 bytes -> 32
 * chars per iteration. Requires AVX2 (runtime-dispatched, never called
 * on CPUs without AVX2).
 */
#include "simd.h"
#include <immintrin.h>

size_t xmc_base64_tail(const uint8_t *in, size_t in_len, char *out);

static __m256i map_to_ascii_256(__m256i idx) {
    const __m256i x80 = _mm256_set1_epi8((char)0x80);
    const __m256i c99 = _mm256_set1_epi8((char)0x99); /* 25 ^ 0x80: idx > 25 */
    const __m256i cb3 = _mm256_set1_epi8((char)0xB3);
    const __m256i cbe = _mm256_set1_epi8((char)0xBE);
    const __m256i cbf = _mm256_set1_epi8((char)0xBF);
    const __m256i c41 = _mm256_set1_epi8(0x41);
    const __m256i c47 = _mm256_set1_epi8(0x47);
    const __m256i cfc = _mm256_set1_epi8((char)0xFC);
    const __m256i c2b = _mm256_set1_epi8(0x2B);
    const __m256i c2f = _mm256_set1_epi8(0x2F);

    const __m256i ix = _mm256_xor_si256(idx, x80);
    __m256i v = _mm256_add_epi8(idx, c41);

    __m256i m = _mm256_cmpgt_epi8(ix, c99);
    v = _mm256_or_si256(_mm256_andnot_si256(m, v),
                        _mm256_and_si256(_mm256_add_epi8(idx, c47), m));
    m = _mm256_cmpgt_epi8(ix, cb3);
    v = _mm256_or_si256(_mm256_andnot_si256(m, v),
                        _mm256_and_si256(_mm256_add_epi8(idx, cfc), m));
    m = _mm256_cmpeq_epi8(ix, cbe);
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(c2b, m));
    m = _mm256_cmpeq_epi8(ix, cbf);
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(c2f, m));
    return v;
}

size_t xmc_base64_encode_avx2(const uint8_t *in, size_t in_len, char *out) {
    const __m256i m63 = _mm256_set1_epi32(0x0000003Fu);  /* keep low 6 bits of each lane */
    /* per-lane: reverse 3-byte group (b2 b1 b0), zero 4th byte */
    const __m256i rev = _mm256_setr_epi8(
        2, 1, 0, -1,   5, 4, 3, -1,   8, 7, 6, -1,   11, 10, 9, -1,
        2, 1, 0, -1,   5, 4, 3, -1,   8, 7, 6, -1,   11, 10, 9, -1);
    size_t o = 0;

    while (in_len >= 24) {
        __m128i lo0 = _mm_cvtsi64_si128(*(const long long *)(in));
        __m128i hi0 = _mm_cvtsi32_si128(*(const int *)(in + 8));
        __m128i lo1 = _mm_cvtsi64_si128(*(const long long *)(in + 12));
        __m128i hi1 = _mm_cvtsi32_si128(*(const int *)(in + 20));
        __m128i lane0 = _mm_unpacklo_epi64(lo0, hi0);
        __m128i lane1 = _mm_unpacklo_epi64(lo1, hi1);
        __m256i v = _mm256_set_m128i(lane1, lane0);

        __m256i x = _mm256_shuffle_epi8(v, rev);  /* big-endian groups */
        __m256i c0 = _mm256_and_si256(_mm256_srli_epi32(x, 18), m63);
        __m256i c1 = _mm256_and_si256(_mm256_srli_epi32(x, 12), m63);
        __m256i c2 = _mm256_and_si256(_mm256_srli_epi32(x, 6), m63);
        __m256i c3 = _mm256_and_si256(x, m63);
        __m256i idx = _mm256_or_si256(
            _mm256_or_si256(c0, _mm256_slli_epi32(c1, 8)),
            _mm256_or_si256(_mm256_slli_epi32(c2, 16), _mm256_slli_epi32(c3, 24)));

        _mm256_storeu_si256((__m256i *)(out + o), map_to_ascii_256(idx));
        in += 24; in_len -= 24; o += 32;
    }
    return o + xmc_base64_tail(in, in_len, out + o);
}
