/*
 * base64 encode - SSSE3 variant (works on all x86-64 CPUs).
 *
 * Processes 12 input bytes per iteration (4 x 3-byte groups, one per
 * 32-bit lane):
 *   - load bytes 0..7 (cvtsi64) and 8..11 (cvtsi32); pack into a 128-bit
 *     vector; bytes 12..15 are zero.
 *   - pshufb reverses each lane's 3 bytes so the group reads big-endian
 *     (b0 at the top) and zeroes the 4th lane.
 *   - extract four 6-bit indices per lane with shifts.
 *   - convert indices to ASCII with branchless compare/mask mapping.
 */
#include "simd.h"
#include <emmintrin.h>
#include <tmmintrin.h>

size_t xmc_base64_tail(const uint8_t *in, size_t in_len, char *out);

static __m128i map_to_ascii(__m128i idx) {
    /* idx bytes are 6-bit values 0..63. Branchless mapping:
     *   0..25  -> 'A'+i          (0x41 + i)
     *   26..51 -> 'a'+i-26       (i + 0x47)
     *   52..61 -> '0'+i-52       (i - 0x04)
     *   62 -> '+', 63 -> '/'
     * Signed compare trick: x ^ 0x80 turns unsigned compare into signed. */
    const __m128i x80 = _mm_set1_epi8((char)0x80);
    const __m128i c99 = _mm_set1_epi8((char)0x99); /* 25 ^ 0x80: idx > 25 */
    const __m128i cb3 = _mm_set1_epi8((char)0xB3); /* 52 ^ 0x80 */
    const __m128i cbe = _mm_set1_epi8((char)0xBE); /* 62 ^ 0x80 */
    const __m128i cbf = _mm_set1_epi8((char)0xBF); /* 63 ^ 0x80 */
    const __m128i c41 = _mm_set1_epi8(0x41);
    const __m128i c47 = _mm_set1_epi8(0x47);
    const __m128i cfc = _mm_set1_epi8((char)0xFC); /* -4 */
    const __m128i c2b = _mm_set1_epi8(0x2B); /* '+' */
    const __m128i c2f = _mm_set1_epi8(0x2F); /* '/' */

    const __m128i ix = _mm_xor_si128(idx, x80);
    __m128i v = _mm_add_epi8(idx, c41);

    __m128i m = _mm_cmpgt_epi8(ix, c99);
    v = _mm_or_si128(_mm_andnot_si128(m, v),
                     _mm_and_si128(_mm_add_epi8(idx, c47), m));
    m = _mm_cmpgt_epi8(ix, cb3);
    v = _mm_or_si128(_mm_andnot_si128(m, v),
                     _mm_and_si128(_mm_add_epi8(idx, cfc), m));
    m = _mm_cmpeq_epi8(ix, cbe);
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(c2b, m));
    m = _mm_cmpeq_epi8(ix, cbf);
    v = _mm_or_si128(_mm_andnot_si128(m, v), _mm_and_si128(c2f, m));
    return v;
}

size_t xmc_base64_encode_sse2(const uint8_t *in, size_t in_len, char *out) {
    const __m128i m63 = _mm_set1_epi32(0x0000003Fu);  /* keep low 6 bits of each lane */
    /* reverse each 3-byte group: (b2 b1 b0), zero the 4th lane */
    const __m128i rev = _mm_setr_epi8(
        2, 1, 0, -1,   5, 4, 3, -1,
        8, 7, 6, -1,   11, 10, 9, -1);
    size_t o = 0;

    while (in_len >= 12) {
        __m128i lo = _mm_cvtsi64_si128(*(const long long *)(in));
        __m128i hi = _mm_cvtsi32_si128(*(const int *)(in + 8));
        __m128i v = _mm_unpacklo_epi64(lo, hi);

        __m128i x = _mm_shuffle_epi8(v, rev);   /* big-endian 24-bit groups */
        __m128i c0 = _mm_and_si128(_mm_srli_epi32(x, 18), m63);
        __m128i c1 = _mm_and_si128(_mm_srli_epi32(x, 12), m63);
        __m128i c2 = _mm_and_si128(_mm_srli_epi32(x, 6), m63);
        __m128i c3 = _mm_and_si128(x, m63);
        __m128i idx = _mm_or_si128(
            _mm_or_si128(c0, _mm_slli_epi32(c1, 8)),
            _mm_or_si128(_mm_slli_epi32(c2, 16), _mm_slli_epi32(c3, 24)));

        _mm_storeu_si128((__m128i *)(out + o), map_to_ascii(idx));
        in += 12; in_len -= 12; o += 16;
    }
    return o + xmc_base64_tail(in, in_len, out + o);
}
