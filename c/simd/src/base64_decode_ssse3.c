/*
 * base64 decode - SSSE3 variant (all x86-64 CPUs).
 *
 * Per 16 input chars (4 x 4-char lanes):
 *   - branchless char->index mapping (compare/mask, same trick as encoder)
 *   - validity check via movemask
 *   - 32-bit lane packing: 4 x 6-bit indices -> 3 bytes per lane
 *   - pshufb gathers 4 lanes (16 bytes) into 12 output bytes
 * Tail (0..3 chars + padding) falls back to the scalar decoder.
 */
#include "simd.h"
#include <emmintrin.h>
#include <tmmintrin.h>

size_t xmc_base64_decode_scalar(const uint8_t *in, size_t in_len, uint8_t *out);

/* char -> 6-bit index, 16 bytes at once; garbage for invalid chars */
static __m128i map_idx(__m128i c) {
    const __m128i x80 = _mm_set1_epi8((char)0x80);
    const __m128i e0 = _mm_set1_epi8((char)0xE0);  /* 'a'^0x80 - 1 */
    const __m128i c0 = _mm_set1_epi8((char)0xC0);  /* 'A'^0x80 - 1 */
    const __m128i a0 = _mm_set1_epi8((char)0xAF);  /* '0'^0x80 - 1 */
    const __m128i bf = _mm_set1_epi8((char)0xBF);  /* -0x41 */
    const __m128i b9 = _mm_set1_epi8((char)0xB9);  /* -0x47 */
    const __m128i p4 = _mm_set1_epi8((char)0x04);
    const __m128i c62 = _mm_set1_epi8(62);
    const __m128i c63 = _mm_set1_epi8(63);
    const __m128i pl = _mm_set1_epi8('+');
    const __m128i sl = _mm_set1_epi8('/');

    const __m128i ix = _mm_xor_si128(c, x80);
    __m128i v = _mm_add_epi8(c, bf);        /* c - 'A' */

    __m128i m = _mm_cmpgt_epi8(ix, e0);     /* c >= 'a' */
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(_mm_add_epi8(c, b9), m));
    /* digits: c >= '0' && c < 'A' (mask out the A-Z / a-z ranges) */
    m = _mm_andnot_si128(_mm_cmpgt_epi8(ix, c0), _mm_cmpgt_epi8(ix, a0));
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(_mm_add_epi8(c, p4), m));
    m = _mm_cmpeq_epi8(c, pl);
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(c62, m));
    m = _mm_cmpeq_epi8(c, sl);
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(c63, m));
    return v;
}

/* validity mask: 0xFF per byte if the char is a legal base64 char */
static __m128i valid_mask(__m128i c) {
    const __m128i x80 = _mm_set1_epi8((char)0x80);
    const __m128i a0 = _mm_set1_epi8((char)0xAF);  /* '0'^0x80 - 1 */
    const __m128i b9 = _mm_set1_epi8((char)0xB9);  /* '9'^0x80 */
    const __m128i c0 = _mm_set1_epi8((char)0xC0);  /* 'A'^0x80 - 1 */
    const __m128i da = _mm_set1_epi8((char)0xDA);  /* 'Z'^0x80 */
    const __m128i e0 = _mm_set1_epi8((char)0xE0);  /* 'a'^0x80 - 1 */
    const __m128i fa = _mm_set1_epi8((char)0xFA);  /* 'z'^0x80 */

    const __m128i ix = _mm_xor_si128(c, x80);
    __m128i digit = _mm_andnot_si128(_mm_cmpgt_epi8(ix, b9), _mm_cmpgt_epi8(ix, a0));
    __m128i upper = _mm_andnot_si128(_mm_cmpgt_epi8(ix, da), _mm_cmpgt_epi8(ix, c0));
    __m128i lower = _mm_andnot_si128(_mm_cmpgt_epi8(ix, fa), _mm_cmpgt_epi8(ix, e0));
    __m128i v = _mm_or_si128(_mm_or_si128(digit, upper),
                             _mm_or_si128(lower, _mm_cmpeq_epi8(c, _mm_set1_epi8('+'))));
    v = _mm_or_si128(v, _mm_cmpeq_epi8(c, _mm_set1_epi8('/')));
    return v;
}

size_t xmc_base64_decode_ssse3(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len % 4 == 1) return (size_t)-1;

    /* SIMD loop only over full 16-char blocks; rest goes to scalar.
     * '=' padding is excluded up front: find the effective length. */
    size_t eff = in_len;
    while (eff > 0 && in[eff - 1] == '=') eff--;
    size_t main_len = eff - (eff % 4);
    size_t ci = 0, o = 0;

    const __m128i m3f = _mm_set1_epi32(0x3F3F3F3Fu);
    const __m128i m0f = _mm_set1_epi32(0x0F0F0F0Fu);
    const __m128i m03 = _mm_set1_epi32(0x03030303u);
    const __m128i gather = _mm_setr_epi8(
        0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, -1, -1, -1, -1);

    while (main_len - ci >= 16) {
        __m128i c = _mm_loadu_si128((const __m128i *)(in + ci));

        if (_mm_movemask_epi8(valid_mask(c)) != 0xFFFF)
            return (size_t)-1;

        __m128i idx = map_idx(c);
        /* lane packing: extract each index byte, then combine:
         *   b0 = i0<<2 | i1>>4 ; b1 = (i1&15)<<4 | (i2&63)>>2 ; b2 = (i2&3)<<6 | i3 */
        const __m128i mff = _mm_set1_epi32(0x000000FFu);
        const __m128i m0f = _mm_set1_epi32(0x0000000Fu);
        const __m128i m03 = _mm_set1_epi32(0x00000003u);
        __m128i i0v = _mm_and_si128(idx, mff);
        __m128i i1v = _mm_and_si128(_mm_srli_epi32(idx, 8), mff);
        __m128i i2v = _mm_and_si128(_mm_srli_epi32(idx, 16), mff);
        __m128i i3v = _mm_and_si128(_mm_srli_epi32(idx, 24), mff);
        __m128i b0 = _mm_or_si128(_mm_slli_epi32(i0v, 2), _mm_srli_epi32(i1v, 4));
        __m128i b1 = _mm_or_si128(_mm_slli_epi32(_mm_and_si128(i1v, m0f), 4),
                                  _mm_srli_epi32(_mm_and_si128(i2v, _mm_set1_epi32(0x3F)), 2));
        __m128i b2 = _mm_or_si128(_mm_slli_epi32(_mm_and_si128(i2v, m03), 6), i3v);
        __m128i packed = _mm_or_si128(b0, _mm_or_si128(_mm_slli_epi32(b1, 8), _mm_slli_epi32(b2, 16)));

        _mm_storeu_si128((__m128i *)(out + o), _mm_shuffle_epi8(packed, gather));
        ci += 16;
        o += 12;
    }

    /* tail: remaining chars (may include padding) */
    size_t n = xmc_base64_decode_scalar(in + ci, in_len - ci, out + o);
    if (n == (size_t)-1) return (size_t)-1;
    return o + n;
}
