/*
 * base64 decode - AVX2 variant. Same algorithm as the SSSE3 variant,
 * 256-bit: two 128-bit lanes, 32 input chars -> 24 output bytes/iter.
 * Requires AVX2 (runtime-dispatched).
 */
#include "simd.h"
#include <immintrin.h>

size_t xmc_base64_decode_scalar(const uint8_t *in, size_t in_len, uint8_t *out);

static __m256i map_idx_256(__m256i c) {
    const __m256i x80 = _mm256_set1_epi8((char)0x80);
    const __m256i e0 = _mm256_set1_epi8((char)0xE0);
    const __m256i c0 = _mm256_set1_epi8((char)0xC0);
    const __m256i a0 = _mm256_set1_epi8((char)0xAF);
    const __m256i bf = _mm256_set1_epi8((char)0xBF);
    const __m256i b9 = _mm256_set1_epi8((char)0xB9);
    const __m256i p4 = _mm256_set1_epi8((char)0x04);
    const __m256i c62 = _mm256_set1_epi8(62);
    const __m256i c63 = _mm256_set1_epi8(63);

    const __m256i ix = _mm256_xor_si256(c, x80);
    __m256i v = _mm256_add_epi8(c, bf);

    __m256i m = _mm256_cmpgt_epi8(ix, e0);
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(_mm256_add_epi8(c, b9), m));
    /* digits: c >= '0' && c < 'A' */
    m = _mm256_andnot_si256(_mm256_cmpgt_epi8(ix, c0), _mm256_cmpgt_epi8(ix, a0));
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(_mm256_add_epi8(c, p4), m));
    m = _mm256_cmpeq_epi8(c, _mm256_set1_epi8('+'));
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(c62, m));
    m = _mm256_cmpeq_epi8(c, _mm256_set1_epi8('/'));
    v = _mm256_or_si256(_mm256_andnot_si256(m, v), _mm256_and_si256(c63, m));
    return v;
}

static __m256i valid_mask_256(__m256i c) {
    const __m256i x80 = _mm256_set1_epi8((char)0x80);
    const __m256i a0 = _mm256_set1_epi8((char)0xAF);
    const __m256i b9 = _mm256_set1_epi8((char)0xB9);
    const __m256i c0 = _mm256_set1_epi8((char)0xC0);
    const __m256i da = _mm256_set1_epi8((char)0xDA);
    const __m256i e0 = _mm256_set1_epi8((char)0xE0);
    const __m256i fa = _mm256_set1_epi8((char)0xFA);

    const __m256i ix = _mm256_xor_si256(c, x80);
    __m256i digit = _mm256_andnot_si256(_mm256_cmpgt_epi8(ix, b9), _mm256_cmpgt_epi8(ix, a0));
    __m256i upper = _mm256_andnot_si256(_mm256_cmpgt_epi8(ix, da), _mm256_cmpgt_epi8(ix, c0));
    __m256i lower = _mm256_andnot_si256(_mm256_cmpgt_epi8(ix, fa), _mm256_cmpgt_epi8(ix, e0));
    __m256i v = _mm256_or_si256(_mm256_or_si256(digit, upper),
                                _mm256_or_si256(lower, _mm256_cmpeq_epi8(c, _mm256_set1_epi8('+'))));
    v = _mm256_or_si256(v, _mm256_cmpeq_epi8(c, _mm256_set1_epi8('/')));
    return v;
}

size_t xmc_base64_decode_avx2(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len % 4 == 1) return (size_t)-1;

    size_t eff = in_len;
    while (eff > 0 && in[eff - 1] == '=') eff--;
    size_t main_len = eff - (eff % 4);
    size_t ci = 0, o = 0;

    const __m256i m3f = _mm256_set1_epi32(0x3F3F3F3Fu);
    const __m256i m0f = _mm256_set1_epi32(0x0F0F0F0Fu);
    const __m256i m03 = _mm256_set1_epi32(0x03030303u);
    const __m256i gather = _mm256_setr_epi8(
        0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, -1, -1, -1, -1,
        16, 17, 18, 20, 21, 22, 24, 25, 26, 28, 29, 30, -1, -1, -1, -1);

    while (main_len - ci >= 32) {
        __m256i c = _mm256_loadu_si256((const __m256i *)(in + ci));

        if (_mm256_movemask_epi8(valid_mask_256(c)) != 0xFFFFFFFF)
            return (size_t)-1;

        __m256i idx = map_idx_256(c);
        const __m256i mff = _mm256_set1_epi32(0x000000FFu);
        const __m256i m0f = _mm256_set1_epi32(0x0000000Fu);
        const __m256i m03 = _mm256_set1_epi32(0x00000003u);
        const __m256i m3f2 = _mm256_set1_epi32(0x3Fu);
        __m256i i0v = _mm256_and_si256(idx, mff);
        __m256i i1v = _mm256_and_si256(_mm256_srli_epi32(idx, 8), mff);
        __m256i i2v = _mm256_and_si256(_mm256_srli_epi32(idx, 16), mff);
        __m256i i3v = _mm256_and_si256(_mm256_srli_epi32(idx, 24), mff);
        __m256i b0 = _mm256_or_si256(_mm256_slli_epi32(i0v, 2), _mm256_srli_epi32(i1v, 4));
        __m256i b1 = _mm256_or_si256(_mm256_slli_epi32(_mm256_and_si256(i1v, m0f), 4),
                                     _mm256_srli_epi32(_mm256_and_si256(i2v, m3f2), 2));
        __m256i b2 = _mm256_or_si256(_mm256_slli_epi32(_mm256_and_si256(i2v, m03), 6), i3v);
        __m256i packed = _mm256_or_si256(b0, _mm256_or_si256(_mm256_slli_epi32(b1, 8), _mm256_slli_epi32(b2, 16)));

        /* gather: low lane -> bytes 0-11, high lane -> bytes 16-27;
         * permutevar8x32 moves the high lane's data to bytes 12-23 */
        __m256i g = _mm256_shuffle_epi8(packed, gather);
        const __m256i perm = _mm256_setr_epi32(0, 1, 2, 4, 5, 6, 3, 7);
        _mm256_storeu_si256((__m256i *)(out + o), _mm256_permutevar8x32_epi32(g, perm));
        ci += 32;
        o += 24;
    }

    size_t n = xmc_base64_decode_scalar(in + ci, in_len - ci, out + o);
    if (n == (size_t)-1) return (size_t)-1;
    return o + n;
}
