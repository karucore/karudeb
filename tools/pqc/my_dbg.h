//  my_dbg.h
//  2023-10-11  Markku-Juhani O. Saarinen <mjos@iki.fi>

//  === Debug printouts and checksum

#ifndef _MY_DBG_H_
#define _MY_DBG_H_

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

//  [debug] dump a hex in indexed format (suitable for comparison)

static inline void dbg_hex(const char *label, const void *data, size_t data_sz)
{
    size_t i;
    const uint8_t *vu8 = data;

    printf("%s = (%zu)", label, data_sz);
    for (i = 0; i < data_sz; i++) {
        if ((i & 0x1F) == 0)
            printf("\n%s[%06zx]: ", label, i);
        printf("%02x", vu8[i]);
    }
    printf("\n");
}

//  [debug] dump a hex string in kat format

static inline void dbg_kat(const char *label, const void *data, size_t data_sz)
{
    size_t i;
    const uint8_t *vu8 = data;

    printf("%s = ", label);
    for (i = 0; i < data_sz; i++) {
        printf("%02X", vu8[i]);
    }
    printf("\n");
}

//  [debug] dump a hex string in C format

static inline void dbg_hexc(const char *lab, const uint8_t *data,
                            size_t data_sz)
{
    size_t i;
    printf("uint8_t %s[%zu] = {", lab, data_sz);
    for (i = 0; i < data_sz; i++) {
        if (i % 12 == 0) {
            printf("\n   ");
        }
        printf(" 0x%02X,", data[i]);
    }
    printf("\n};\n");
}

static inline uint32_t crc32byte(uint32_t x, const uint8_t c)
{
    x ^= ((uint32_t) c) << 24;

    for (int i = 0; i < 8; i++) {
        x = (x << 1) ^ ((-(x >> 31)) & 0x04C11DB7);
    }

    return x;
}

//  checksums

static inline uint32_t dbg_chk(const char *label, const void *data,
                               size_t data_sz, uint32_t chk)
{
    int fail;
    size_t i;
    uint32_t x = 0;
    uint64_t l;
    const uint8_t *vu8 = data;

    //        compatible with cksum(1)
    for (i = 0; i < data_sz; i++) {
        x = crc32byte(x, vu8[i]);
    }
    l = data_sz;
    while (l != 0) {
        x = crc32byte(x, l & 0xFF);
        l >>= 8;
    }
    x = ~x;

    fail = x != chk;

    printf("[%s]\t%s: %08X [%08X] (%zu)\n",
        fail ? "FAIL" : "PASS", label, x, chk, data_sz);

    return fail;
}

//  set a string

static inline size_t dbg_set(uint8_t *r, const char *hex)
{
    size_t i, j;
    int f, x, y;

    i = 0;
    j = 0;
    f = 0;
    x = 0;
    y = 0;

    while (1) {
        x = hex[i++];
        if (x == ' ' || x == '\t' || x == '\n')
            continue;
        if (x >= '0' && x <= '9') {
            x -= '0';
        } else if (x >= 'a' && x <= 'f') {
            x -= 'a' - 10;
        } else if (x >= 'A' && x <= 'F') {
            x -= 'A' - 10;
        } else {
            return j;
        }
        x &= 0xF;
        if (f == 0) {
            y = x;
            f = 1;
        } else {
            r[j++] = (uint8_t) ((y << 4) | x);
            f = 0;
        }
    }
    return j;
}

static inline uint32_t dbg_clk(const char *func, uint64_t cc)
{
    printf("[CLK]\t%12lu %s\n", cc, func);

    return (uint32_t) cc;
}

//  _MY_DBG_H_
#endif
