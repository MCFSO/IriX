/*
 * base64 encode - scalar reference implementation (RFC 4648 with padding).
 */
#include "simd.h"

static const char B64_TBL[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t xmc_base64_encoded_len(size_t in_len) {
    return ((in_len + 2) / 3) * 4;
}

/* Shared scalar tail used by all variants. Returns chars written. */
size_t xmc_base64_tail(const uint8_t *in, size_t in_len, char *out);

size_t xmc_base64_tail(const uint8_t *in, size_t in_len, char *out) {
    size_t o = 0;
    while (in_len >= 3) {
        const uint32_t v = ((uint32_t)in[0] << 16) | ((uint32_t)in[1] << 8) | in[2];
        out[o++] = B64_TBL[(v >> 18) & 0x3F];
        out[o++] = B64_TBL[(v >> 12) & 0x3F];
        out[o++] = B64_TBL[(v >> 6) & 0x3F];
        out[o++] = B64_TBL[v & 0x3F];
        in += 3; in_len -= 3;
    }
    if (in_len == 2) {
        const uint32_t v = ((uint32_t)in[0] << 16) | ((uint32_t)in[1] << 8);
        out[o++] = B64_TBL[(v >> 18) & 0x3F];
        out[o++] = B64_TBL[(v >> 12) & 0x3F];
        out[o++] = B64_TBL[(v >> 6) & 0x3F];
        out[o++] = '=';
    } else if (in_len == 1) {
        const uint32_t v = (uint32_t)in[0] << 16;
        out[o++] = B64_TBL[(v >> 18) & 0x3F];
        out[o++] = B64_TBL[(v >> 12) & 0x3F];
        out[o++] = '=';
        out[o++] = '=';
    }
    return o;
}

size_t xmc_base64_encode_scalar(const uint8_t *in, size_t in_len, char *out) {
    return xmc_base64_tail(in, in_len, out);
}
