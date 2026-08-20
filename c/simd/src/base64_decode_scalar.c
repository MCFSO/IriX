/*
 * base64 decode - scalar reference implementation (RFC 4648, optional padding).
 * Validates characters; returns SIZE_MAX on invalid input.
 */
#include "simd.h"
#include <limits.h>

static int8_t g_dec[256];
static int g_dec_ready = 0;

static void init_table(void) {
    if (g_dec_ready) return;
    for (int i = 0; i < 256; i++) g_dec[i] = -1;
    for (int i = 0; i < 26; i++) g_dec['A' + i] = (int8_t)i;
    for (int i = 0; i < 26; i++) g_dec['a' + i] = (int8_t)(26 + i);
    for (int i = 0; i < 10; i++) g_dec['0' + i] = (int8_t)(52 + i);
    g_dec['+'] = 62;
    g_dec['/'] = 63;
    g_dec_ready = 1;
}

size_t xmc_base64_decoded_len(size_t in_len) {
    /* worst case: every 4 chars produce 3 bytes */
    return (in_len / 4) * 3 + 3;
}

size_t xmc_base64_decode_scalar(const uint8_t *in, size_t in_len, uint8_t *out) {
    init_table();
    if (in_len % 4 == 1) return SIZE_MAX;   /* impossible length */

    size_t o = 0;
    size_t i = 0;
    for (; i + 4 <= in_len; i += 4) {
        /* padding groups: "XX==" -> 1 byte, "XXX=" -> 2 bytes */
        if (in[i + 2] == '=') {   /* XX== */
            if (in[i + 3] != '=') return SIZE_MAX;
            if (in_len - i != 4) return SIZE_MAX;   /* padding must end input */
            const int a = g_dec[in[i]], b = g_dec[in[i + 1]];
            if (a < 0 || b < 0) return SIZE_MAX;
            if ((b & 0x0F) != 0) return SIZE_MAX;   /* unused 4 bits must be zero */
            out[o++] = (uint8_t)((a << 2) | (b >> 4));
            return o;
        }
        if (in[i + 3] == '=') {   /* XXX= */
            if (in_len - i != 4) return SIZE_MAX;
            const int a = g_dec[in[i]], b = g_dec[in[i + 1]], c = g_dec[in[i + 2]];
            if (a < 0 || b < 0 || c < 0) return SIZE_MAX;
            if ((c & 0x03) != 0) return SIZE_MAX;   /* unused 2 bits must be zero */
            out[o++] = (uint8_t)((a << 2) | (b >> 4));
            out[o++] = (uint8_t)((b << 4) | (c >> 2));
            return o;
        }
        if (in[i] == '=' || in[i + 1] == '=') return SIZE_MAX;   /* misplaced padding */

        const int a = g_dec[in[i]], b = g_dec[in[i + 1]];
        const int c = g_dec[in[i + 2]], d = g_dec[in[i + 3]];
        if (a < 0 || b < 0 || c < 0 || d < 0) return SIZE_MAX;
        out[o++] = (uint8_t)((a << 2) | (b >> 4));
        out[o++] = (uint8_t)((b << 4) | (c >> 2));
        out[o++] = (uint8_t)((c << 6) | d);
    }
    /* trailing 2 or 3 chars without padding (in_len % 4 == 2 or 3) */
    if (in_len - i == 2) {
        const int a = g_dec[in[i]], b = g_dec[in[i + 1]];
        if (a < 0 || b < 0) return SIZE_MAX;
        if ((b & 0x0F) != 0) return SIZE_MAX;
        out[o++] = (uint8_t)((a << 2) | (b >> 4));
    } else if (in_len - i == 3) {
        const int a = g_dec[in[i]], b = g_dec[in[i + 1]], c = g_dec[in[i + 2]];
        if (a < 0 || b < 0 || c < 0) return SIZE_MAX;
        if ((c & 0x03) != 0) return SIZE_MAX;
        out[o++] = (uint8_t)((a << 2) | (b >> 4));
        out[o++] = (uint8_t)((b << 4) | (c >> 2));
    }
    return o;
}
