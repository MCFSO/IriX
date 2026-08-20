/* crc_debug.c - find the first length where pclmul differs from slice8 */
#include "simd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    uint8_t buf[512];
    srand(7);
    for (int i = 0; i < 512; i++) buf[i] = (uint8_t)rand();

    printf("len  slice8      pclmul      match\n");
    for (size_t len = 0; len <= 256; len++) {
        uint32_t a = xmc_crc32_ieee_slice8(buf, len, 0);
        uint32_t b = xmc_crc32_ieee_pclmul(buf, len, 0);
        if (a != b) {
            printf("%3zu  0x%08X  0x%08X   MISMATCH\n", len, a, b);
            if (len > 40) break; /* stop after first region */
        }
    }
    return 0;
}
