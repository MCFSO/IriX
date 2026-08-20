/*
 * CRC32C (Castagnoli, poly 0x82F63B78) via the SSE4.2 crc32 instruction.
 * Hardware instruction, ~50 GB/s class throughput; used by iSCSI/Redis/etc.
 */
#include "simd.h"
#include <nmmintrin.h>
#include <string.h>

uint32_t xmc_crc32c(const uint8_t *data, size_t len, uint32_t seed) {
    uint32_t crc = seed ^ 0xFFFFFFFFu;
    while (len >= 8) {
        uint64_t v;
        memcpy(&v, data, 8);
        crc = (uint32_t)_mm_crc32_u64(crc, v);
        data += 8; len -= 8;
    }
    while (len >= 4) {
        uint32_t v;
        memcpy(&v, data, 4);
        crc = _mm_crc32_u32(crc, v);
        data += 4; len -= 4;
    }
    while (len--) {
        crc = _mm_crc32_u8(crc, *data++);
    }
    return crc ^ 0xFFFFFFFFu;
}
