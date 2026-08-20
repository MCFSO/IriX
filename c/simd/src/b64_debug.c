/* b64_debug.c - find first mismatch between scalar and sse2/avx2 */
#include "simd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    uint8_t buf[64];
    char s1[128], s2[128];
    srand(11);
    for (int i = 0; i < 64; i++) buf[i] = (uint8_t)rand();

    for (size_t len = 0; len <= 60; len++) {
        size_t n1 = xmc_base64_encode_scalar(buf, len, s1);
        size_t n2 = xmc_base64_encode_sse2(buf, len, s2);
        if (n1 != n2 || memcmp(s1, s2, n1)) {
            printf("len=%zu: sse2 mismatch (n1=%zu n2=%zu)\n", len, n1, n2);
            for (size_t i = 0; i < n1; i++) {
                if (s1[i] != s2[i]) {
                    printf("  first diff at out[%zu]: scalar=%02X (%c) sse2=%02X (%c)\n",
                           i, (unsigned char)s1[i], s1[i], (unsigned char)s2[i], s2[i]);
                    break;
                }
            }
            break;
        }
        size_t n3 = xmc_base64_encode_avx2(buf, len, s2);
        if (n1 != n3 || memcmp(s1, s2, n1)) {
            printf("len=%zu: avx2 mismatch (n1=%zu n3=%zu)\n", len, n1, n3);
            for (size_t i = 0; i < n1; i++) {
                if (s1[i] != s2[i]) {
                    printf("  first diff at out[%zu]: scalar=%02X (%c) avx2=%02X (%c)\n",
                           i, (unsigned char)s1[i], s1[i], (unsigned char)s2[i], s2[i]);
                    break;
                }
            }
            break;
        }
    }
    printf("scan done\n");
    return 0;
}
