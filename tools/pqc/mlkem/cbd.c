//  cbd.c

#include <stdint.h>
#include "mlkem_params.h"
#include "cbd.h"

#if MLKEM_RVV != 1
//  load 4 bytes into a 32-bit integer in little-endian order

static uint32_t load32_littleendian(const uint8_t x[4])
{
    uint32_t r;
    r = (uint32_t) x[0];
    r |= (uint32_t) x[1] << 8;
    r |= (uint32_t) x[2] << 16;
    r |= (uint32_t) x[3] << 24;
    return r;
}

//  load 3 bytes into a 32-bit integer in little-endian order.
//  This function is only needed for Kyber-512

static uint32_t load24_littleendian(const uint8_t x[3])
{
    uint32_t r;
    r = (uint32_t) x[0];
    r |= (uint32_t) x[1] << 8;
    r |= (uint32_t) x[2] << 16;
    return r;
}


//  Given an array of uniformly random bytes, compute polynomial with
//  coefficients distributed according to a centered binomial distribution
//  with parameter eta=2

static void cbd2(poly_t *r, const uint8_t buf[2 * MLKEM_PAR_N / 4])
{
    unsigned int i, j;
    uint32_t t, d;
    int16_t a, b;

    for (i = 0; i < MLKEM_PAR_N / 8; i++) {
        t = load32_littleendian(buf + 4 * i);
        d = t & 0x55555555;
        d += (t >> 1) & 0x55555555;

        for (j = 0; j < 8; j++) {
            a = (d >> (4 * j + 0)) & 0x3;
            b = (d >> (4 * j + 2)) & 0x3;
            r->coeffs[8 * i + j] = a - b;
        }
    }
}

//  Given an array of uniformly random bytes, compute
//  polynomial with coefficients distributed according to
//  a centered binomial distribution with parameter eta=3.
//  This function is only needed for Kyber-512

static void cbd3(poly_t *r, const uint8_t buf[3 * MLKEM_PAR_N / 4])
{
    unsigned int i, j;
    uint32_t t, d;
    int16_t a, b;

    for (i = 0; i < MLKEM_PAR_N / 4; i++) {
        t = load24_littleendian(buf + 3 * i);
        d = t & 0x00249249;
        d += (t >> 1) & 0x00249249;
        d += (t >> 2) & 0x00249249;

        for (j = 0; j < 4; j++) {
            a = (d >> (6 * j + 0)) & 0x7;
            b = (d >> (6 * j + 3)) & 0x7;
            r->coeffs[4 * i + j] = a - b;
        }
    }
}
#endif /* MLKEM_RVV != 1 */

#if MLKEM_RVV == 1
/* Vector CBD2/CBD3 — see cbd_rvv.c. Both gated under MLKEM_RVV so
 * the original scalar reference (above) stays intact for "reference
 * implementation" timing claims. */
void cbd2_rvv(int16_t *r, const uint8_t *buf);
void cbd3_rvv(int16_t *r, const uint8_t *buf);
#endif

void poly_cbd_eta1(const mlkem_param_t *par, poly_t *r, const uint8_t *buf)
{
    if (par->eta1 == 2) {
#if MLKEM_RVV == 1
        cbd2_rvv(r->coeffs, buf);
#else
        cbd2(r, buf);
#endif
    } else {
        //  #elif MLKEM_ETA1 == 3
#if MLKEM_RVV == 1
        cbd3_rvv(r->coeffs, buf);
#else
        cbd3(r, buf);
#endif
    }
}

void poly_cbd_eta2(poly_t *r, const uint8_t *buf)
{
#if MLKEM_PAR_ETA2 == 2
#if MLKEM_RVV == 1
    cbd2_rvv(r->coeffs, buf);
#else
    cbd2(r, buf);
#endif
#else
#error "This implementation requires eta2 = 2"
#endif
}
