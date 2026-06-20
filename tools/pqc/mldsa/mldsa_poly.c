//  mldsa_poly.c

#include <stdint.h>
#include "mldsa_params.h"
#include "mldsa_poly.h"
#include "mldsa_ntt.h"
#include "mldsa_reduce.h"
#include "symmetric.h"

//  For finite field element a, compute a0, a1 such that
//  a mod^+ Q = a1*2^D + a0 with -2^{D-1} < a0 <= 2^{D-1}.
//  Assumes a to be standard representative.

static int32_t power2round(int32_t *a0, int32_t a)
{
    int32_t a1;

    a1 = (a + (1 << (MLDSA_PAR_D - 1)) - 1) >> MLDSA_PAR_D;
    *a0 = a - (a1 << MLDSA_PAR_D);
    return a1;
}

//  For finite field element a, compute high and low bits a0, a1such that
//  a mod^+ Q = a1*ALPHA + a0 with -ALPHA/2 < a0 <= ALPHA/2 except if
//  a1 = (Q-1)/ALPHA where we set a1 = 0 and
//  -ALPHA/2 <= a0 = a mod^+ Q - Q < 0. Assumes a to be standard
//representative.

static int32_t decompose_32(int32_t *a0, int32_t a)
{
    int32_t a1;

    a1 = (a + 127) >> 7;
    a1 = (a1 * 1025 + (1 << 21)) >> 22;
    a1 &= 15;

    *a0 = a - a1 * 2 * ((MLDSA_PAR_Q - 1) / 32);
    *a0 -= (((MLDSA_PAR_Q - 1) / 2 - *a0) >> 31) & MLDSA_PAR_Q;
    return a1;
}

static int32_t decompose_88(int32_t *a0, int32_t a)
{
    int32_t a1;

    a1 = (a + 127) >> 7;
    a1 = (a1 * 11275 + (1 << 23)) >> 24;
    a1 ^= ((43 - a1) >> 31) & a1;

    *a0 = a - a1 * 2 * ((MLDSA_PAR_Q - 1) / 88);
    *a0 -= (((MLDSA_PAR_Q - 1) / 2 - *a0) >> 31) & MLDSA_PAR_Q;
    return a1;
}

//  Compute hint bit indicating whether the low bits of the
//  input element overflow into the high bits.
static unsigned int make_hint(int32_t a0, int32_t a1, int32_t gamma2)
{
    if (a0 > gamma2 || a0 < -gamma2 || (a0 == -gamma2 && a1 != 0)) {
        return 1;
    }
    return 0;
}

//  Correct high bits according to hint.

static int32_t use_hint_32(int32_t a, unsigned int hint)
{
    int32_t a0, a1;

    a1 = decompose_32(&a0, a);
    if (hint == 0)
        return a1;

    if (a0 > 0) {
        return (a1 + 1) & 15;
    } else {
        return (a1 - 1) & 15;
    }
}

static int32_t use_hint_88(int32_t a, unsigned int hint)
{
    int32_t a0, a1;

    a1 = decompose_88(&a0, a);
    if (hint == 0)
        return a1;

    if (a0 > 0) {
        return (a1 == 43) ? 0 : a1 + 1;
    } else {
        return (a1 == 0) ? 43 : a1 - 1;
    }
}

//  Inplace reduction of all coefficients of polynomial to representative in
//  [-6283008,6283008].

void mldsa_poly_reduce(poly_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        a->coeffs[i] = reduce32(a->coeffs[i]);
    }
}

//  For all coefficients of in/out polynomial add Q if x < 0

void poly_caddq(poly_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        a->coeffs[i] = caddq(a->coeffs[i]);
    }
}

//  Add polynomials. No modular reduction is performed.

void mldsa_poly_add(poly_t *c, const poly_t *a, const poly_t *b)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        c->coeffs[i] = a->coeffs[i] + b->coeffs[i];
    }
}

//  Subtract polynomials. No modular reduction is performed.

void mldsa_poly_sub(poly_t *c, const poly_t *a, const poly_t *b)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        c->coeffs[i] = a->coeffs[i] - b->coeffs[i];
    }
}

//  Multiply polynomial by 2^D without modular reduction. Assumes
//  input coefficients to be less than 2^{31-D} in absolute value.

void poly_shiftl(poly_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        a->coeffs[i] <<= MLDSA_PAR_D;
    }
}

//  Inplace forward NTT. Coefficients can grow by 8*Q in absolute value.

void mldsa_poly_ntt(poly_t *a)
{
    mldsa_ntt(a->coeffs);
}

//  Inplace inverse NTT and multiplication by 2^{32}. Input coefficients
//  need to be less than Q in absolute value and output coefficients are
//  again bounded by Q.

void mldsa_poly_invntt_tomont(poly_t *a)
{
    mldsa_invntt(a->coeffs);
}

//  Pointwise multiplication of polynomials in NTT domain representation
//  and multiplication of resulting polynomial by 2^{-32}.

void poly_pointwise_montgomery(poly_t *c, const poly_t *a, const poly_t *b)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        c->coeffs[i] =
            montgomery_reduce((int64_t) a->coeffs[i] * b->coeffs[i]);
    }
}

//  For all coefficients c of the input polynomial, compute c0, c1 such
//  that c mod Q = c1*2^D + c0 with -2^{D-1} < c0 <= 2^{D-1}.
//  Assumes coefficients to be standard representatives.

void poly_power2round(poly_t *a1, poly_t *a0, const poly_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        a1->coeffs[i] = power2round(&a0->coeffs[i], a->coeffs[i]);
    }
}

//  For all coefficients c of the input polynomial, compute high and low
//  bits c0, c1 such c mod Q = c1*ALPHA + c0 with -ALPHA/2 < c0 <= ALPHA/2
//  except c1 = (Q-1)/ALPHA where we set c1 = 0 and
//  -ALPHA/2 <= c0 = c mod Q - Q < 0.
//  Assumes coefficients to be standard representatives.

void poly_decompose(const mldsa_param_t *par, poly_t *a1, poly_t *a0,
                    const poly_t *a)
{
    unsigned int i;

    if (par->gamma2 == (MLDSA_PAR_Q - 1) / 32) {
        for (i = 0; i < MLDSA_PAR_N; i++) {
            a1->coeffs[i] = decompose_32(&a0->coeffs[i], a->coeffs[i]);
        }
    } else {
        // GAMMA2 == (MLDSA_PAR_Q - 1) / 32
        for (i = 0; i < MLDSA_PAR_N; i++) {
            a1->coeffs[i] = decompose_88(&a0->coeffs[i], a->coeffs[i]);
        }
    }
}

//  Compute hint polynomial. The coefficients of which indicate whether
//  the low bits of the corresponding coefficient of the input polynomial
//  overflow into the high bits.

unsigned int poly_make_hint(const mldsa_param_t *par, poly_t *h,
                            const poly_t *a0, const poly_t *a1)
{
    unsigned int i, s = 0;

    for (i = 0; i < MLDSA_PAR_N; i++) {
        h->coeffs[i] = make_hint(a0->coeffs[i], a1->coeffs[i], par->gamma2);
        s += h->coeffs[i];
    }

    return s;
}

//  Use hint polynomial to correct the high bits of a polynomial.

void poly_use_hint(const mldsa_param_t *par, poly_t *b, const poly_t *a,
                   const poly_t *h)
{
    unsigned int i;

    if (par->gamma2 == (MLDSA_PAR_Q - 1) / 32) {
        for (i = 0; i < MLDSA_PAR_N; i++) {
            b->coeffs[i] = use_hint_32(a->coeffs[i], h->coeffs[i]);
        }
    } else {
        for (i = 0; i < MLDSA_PAR_N; i++) {
            b->coeffs[i] = use_hint_88(a->coeffs[i], h->coeffs[i]);
        }
    }
}

//  Check infinity norm of polynomial against given bound.
//  Assumes input coefficients were reduced by reduce32().

int poly_chknorm(const poly_t *a, int32_t bb)
{
    unsigned int i;
    int32_t t;

    if (bb > (MLDSA_PAR_Q - 1) / 8) {
        return 1;
    }

    /* It is ok to leak which coefficient violates the bound since
       the probability for each coefficient is independent of secret
       data but we must not leak the sign of the centralized representative. */
    for (i = 0; i < MLDSA_PAR_N; i++) {
        /* Absolute value */
        t = a->coeffs[i] >> 31;
        t = a->coeffs[i] - (t & 2 * a->coeffs[i]);

        if (t >= bb) {
            return 1;
        }
    }

    return 0;
}

//  Sample uniformly random coefficients in [0, Q-1] by performing
//  rejection sampling on array of random bytes.

#if MLDSA_RVV == 1

//  prototype -- in rvv_poly.c
unsigned int mldsa_rej_uniform(int32_t *a, unsigned int len, const uint8_t *buf,
                         unsigned int buflen);

#else

static unsigned int mldsa_rej_uniform(int32_t *a, unsigned int len,
                                const uint8_t *buf, unsigned int buflen)
{
    unsigned int ctr, pos;
    uint32_t t;

    ctr = pos = 0;
    while (ctr < len && pos + 3 <= buflen) {
        t = buf[pos++];
        t |= (uint32_t) buf[pos++] << 8;
        t |= (uint32_t) buf[pos++] << 16;
        t &= 0x7FFFFF;

        if (t < MLDSA_PAR_Q) {
            a[ctr++] = t;
        }
    }

    return ctr;
}

#endif

//  Sample polynomial with uniformly random coefficients in [0,Q-1] by
//  performing rejection sampling on the output stream of SHAKE128(seed|nonce)

#define POLY_UNIFORM_NBLOCKS \
    ((768 + STREAM128_BLOCKBYTES - 1) / STREAM128_BLOCKBYTES)
void poly_uniform(poly_t *a, const uint8_t seed[MLDSA_SEED_SZ], uint16_t nonce)
{
    unsigned int i, ctr, off;
    unsigned int buflen = POLY_UNIFORM_NBLOCKS * STREAM128_BLOCKBYTES;
    uint8_t buf[POLY_UNIFORM_NBLOCKS * STREAM128_BLOCKBYTES + 2];
    stream128_state state;

    stream128_init(&state, seed, nonce);
    stream128_squeezeblocks(buf, POLY_UNIFORM_NBLOCKS, &state);

    ctr = mldsa_rej_uniform(a->coeffs, MLDSA_PAR_N, buf, buflen);

    while (ctr < MLDSA_PAR_N) {
        off = buflen % 3;
        for (i = 0; i < off; i++) {
            buf[i] = buf[buflen - off + i];
        }

        stream128_squeezeblocks(buf + off, 1, &state);
        buflen = STREAM128_BLOCKBYTES + off;
        ctr += mldsa_rej_uniform(a->coeffs + ctr, MLDSA_PAR_N - ctr, buf, buflen);
    }
}

//  Sample uniformly random coefficients in [-ETA, ETA] by
//  performing rejection sampling on array of random bytes.

static unsigned int rej_eta_2(int32_t *a, unsigned int len, const uint8_t *buf,
                              unsigned int buflen)
{
    unsigned int ctr, pos;
    uint32_t t0, t1;

    ctr = pos = 0;
    while (ctr < len && pos < buflen) {
        t0 = buf[pos] & 0x0F;
        t1 = buf[pos++] >> 4;
        if (t0 < 15) {
            t0 = t0 - (205 * t0 >> 10) * 5;
            a[ctr++] = 2 - t0;
        }
        if (t1 < 15 && ctr < len) {
            t1 = t1 - (205 * t1 >> 10) * 5;
            a[ctr++] = 2 - t1;
        }
    }

    return ctr;
}

static unsigned int rej_eta_4(int32_t *a, unsigned int len, const uint8_t *buf,
                              unsigned int buflen)
{
    unsigned int ctr, pos;
    uint32_t t0, t1;

    ctr = pos = 0;
    while (ctr < len && pos < buflen) {
        t0 = buf[pos] & 0x0F;
        t1 = buf[pos++] >> 4;

        if (t0 < 9) {
            a[ctr++] = 4 - t0;
        }
        if (t1 < 9 && ctr < len) {
            a[ctr++] = 4 - t1;
        }
    }

    return ctr;
}

//  Sample polynomial with uniformly random coefficients in [-ETA,ETA]
//  by performing rejection sampling on the

#define POLY_UNIFORM_ETA_NBLOCKS_2 \
    ((136 + STREAM256_BLOCKBYTES - 1) / STREAM256_BLOCKBYTES)

static void poly_uniform_eta_2(poly_t *a, const uint8_t seed[MLDSA_CRH_SZ],
                               uint16_t nonce)
{
    unsigned int ctr;
    unsigned int buflen = POLY_UNIFORM_ETA_NBLOCKS_2 * STREAM256_BLOCKBYTES;
    uint8_t buf[POLY_UNIFORM_ETA_NBLOCKS_2 * STREAM256_BLOCKBYTES];
    stream256_state state;

    stream256_init(&state, seed, nonce);
    stream256_squeezeblocks(buf, POLY_UNIFORM_ETA_NBLOCKS_2, &state);

    ctr = rej_eta_2(a->coeffs, MLDSA_PAR_N, buf, buflen);

    while (ctr < MLDSA_PAR_N) {
        stream256_squeezeblocks(buf, 1, &state);
        ctr += rej_eta_2(a->coeffs + ctr, MLDSA_PAR_N - ctr, buf,
                         STREAM256_BLOCKBYTES);
    }
}

#define POLY_UNIFORM_ETA_NBLOCKS_4 \
    ((227 + STREAM256_BLOCKBYTES - 1) / STREAM256_BLOCKBYTES)

static void poly_uniform_eta_4(poly_t *a, const uint8_t seed[MLDSA_CRH_SZ],
                               uint16_t nonce)
{
    unsigned int ctr;
    unsigned int buflen = POLY_UNIFORM_ETA_NBLOCKS_4 * STREAM256_BLOCKBYTES;
    uint8_t buf[POLY_UNIFORM_ETA_NBLOCKS_4 * STREAM256_BLOCKBYTES];
    stream256_state state;

    stream256_init(&state, seed, nonce);
    stream256_squeezeblocks(buf, POLY_UNIFORM_ETA_NBLOCKS_4, &state);

    ctr = rej_eta_4(a->coeffs, MLDSA_PAR_N, buf, buflen);

    while (ctr < MLDSA_PAR_N) {
        stream256_squeezeblocks(buf, 1, &state);
        ctr += rej_eta_4(a->coeffs + ctr, MLDSA_PAR_N - ctr, buf,
                         STREAM256_BLOCKBYTES);
    }
}

void poly_uniform_eta(const mldsa_param_t *par, poly_t *a,
                      const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce)
{
    if (par->eta == 2) {
        poly_uniform_eta_2(a, seed, nonce);
    } else if (par->eta == 4) {
        poly_uniform_eta_4(a, seed, nonce);
    }
}

//  Sample polynomial with uniformly random coefficients in
//  [-(GAMMA1 - 1), GAMMA1] by unpacking output stream of SHAKE256(seed|nonce)

void poly_uniform_gamma1(const mldsa_param_t *par, poly_t *a,
                         const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce)
{
    uint8_t buf[((MLDSA_MAX_PZP_SZ + STREAM256_BLOCKBYTES - 1) /
                 STREAM256_BLOCKBYTES) *
                STREAM256_BLOCKBYTES];
    stream256_state state;

    stream256_init(&state, seed, nonce);

    stream256_squeezeblocks(
        buf, ((par->pzp_sz + STREAM256_BLOCKBYTES - 1) / STREAM256_BLOCKBYTES),
        &state);
    polyz_unpack(par, a, buf);
}

//  Implementation of H. Samples polynomial with par->tau nonzero
//  coefficients in {-1,1} using the output stream of SHAKE256(seed).

void poly_challenge(const mldsa_param_t *par, poly_t *c, const uint8_t *seed)
{
    unsigned int i, b, pos;
    uint64_t signs;
    uint8_t buf[SHAKE256_RATE];
    keccak_state state;

    shake256_init(&state);
    shake256_absorb(&state, seed, par->cp_sz);
    shake256_finalize(&state);
    shake256_squeezeblocks(buf, 1, &state);

    signs = 0;
    for (i = 0; i < 8; i++)
        signs |= (uint64_t) buf[i] << 8 * i;
    pos = 8;

    for (i = 0; i < MLDSA_PAR_N; i++)
        c->coeffs[i] = 0;
    for (i = MLDSA_PAR_N - par->tau; i < MLDSA_PAR_N; i++) {
        do {
            if (pos >= SHAKE256_RATE) {
                shake256_squeezeblocks(buf, 1, &state);
                pos = 0;
            }

            b = buf[pos++];
        } while (b > i);

        c->coeffs[i] = c->coeffs[b];
        c->coeffs[b] = 1 - 2 * (signs & 1);
        signs >>= 1;
    }
}

//  Bit-pack polynomial with coefficients in [-ETA,ETA].

void polyeta_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a)
{
    unsigned int i;
    uint8_t t[8];

    if (par->eta == 2) {
        for (i = 0; i < MLDSA_PAR_N / 8; i++) {
            t[0] = 2 - a->coeffs[8 * i + 0];
            t[1] = 2 - a->coeffs[8 * i + 1];
            t[2] = 2 - a->coeffs[8 * i + 2];
            t[3] = 2 - a->coeffs[8 * i + 3];
            t[4] = 2 - a->coeffs[8 * i + 4];
            t[5] = 2 - a->coeffs[8 * i + 5];
            t[6] = 2 - a->coeffs[8 * i + 6];
            t[7] = 2 - a->coeffs[8 * i + 7];

            r[3 * i + 0] = (t[0] >> 0) | (t[1] << 3) | (t[2] << 6);
            r[3 * i + 1] =
                (t[2] >> 2) | (t[3] << 1) | (t[4] << 4) | (t[5] << 7);
            r[3 * i + 2] = (t[5] >> 1) | (t[6] << 2) | (t[7] << 5);
        }
    } else if (par->eta == 4) {
        for (i = 0; i < MLDSA_PAR_N / 2; i++) {
            t[0] = 4 - a->coeffs[2 * i + 0];
            t[1] = 4 - a->coeffs[2 * i + 1];
            r[i] = t[0] | (t[1] << 4);
        }
    }
}

//  Unpack polynomial with coefficients in [-ETA,ETA].

void polyeta_unpack(const mldsa_param_t *par, poly_t *r, const uint8_t *a)
{
    unsigned int i;

    if (par->eta == 2) {
        for (i = 0; i < MLDSA_PAR_N / 8; i++) {
            r->coeffs[8 * i + 0] = (a[3 * i + 0] >> 0) & 7;
            r->coeffs[8 * i + 1] = (a[3 * i + 0] >> 3) & 7;
            r->coeffs[8 * i + 2] =
                ((a[3 * i + 0] >> 6) | (a[3 * i + 1] << 2)) & 7;
            r->coeffs[8 * i + 3] = (a[3 * i + 1] >> 1) & 7;
            r->coeffs[8 * i + 4] = (a[3 * i + 1] >> 4) & 7;
            r->coeffs[8 * i + 5] =
                ((a[3 * i + 1] >> 7) | (a[3 * i + 2] << 1)) & 7;
            r->coeffs[8 * i + 6] = (a[3 * i + 2] >> 2) & 7;
            r->coeffs[8 * i + 7] = (a[3 * i + 2] >> 5) & 7;

            r->coeffs[8 * i + 0] = 2 - r->coeffs[8 * i + 0];
            r->coeffs[8 * i + 1] = 2 - r->coeffs[8 * i + 1];
            r->coeffs[8 * i + 2] = 2 - r->coeffs[8 * i + 2];
            r->coeffs[8 * i + 3] = 2 - r->coeffs[8 * i + 3];
            r->coeffs[8 * i + 4] = 2 - r->coeffs[8 * i + 4];
            r->coeffs[8 * i + 5] = 2 - r->coeffs[8 * i + 5];
            r->coeffs[8 * i + 6] = 2 - r->coeffs[8 * i + 6];
            r->coeffs[8 * i + 7] = 2 - r->coeffs[8 * i + 7];
        }
    } else if (par->eta == 4) {
        for (i = 0; i < MLDSA_PAR_N / 2; i++) {
            r->coeffs[2 * i + 0] = a[i] & 0x0F;
            r->coeffs[2 * i + 1] = a[i] >> 4;
            r->coeffs[2 * i + 0] = 4 - r->coeffs[2 * i + 0];
            r->coeffs[2 * i + 1] = 4 - r->coeffs[2 * i + 1];
        }
    }
}

//  Bit-pack polynomial t1 with coefficients fitting in 10 bits.
//  Input coefficients are assumed to be standard representatives.

void polyt1_pack(uint8_t *r, const poly_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N / 4; i++) {
        r[5 * i + 0] = (a->coeffs[4 * i + 0] >> 0);
        r[5 * i + 1] =
            (a->coeffs[4 * i + 0] >> 8) | (a->coeffs[4 * i + 1] << 2);
        r[5 * i + 2] =
            (a->coeffs[4 * i + 1] >> 6) | (a->coeffs[4 * i + 2] << 4);
        r[5 * i + 3] =
            (a->coeffs[4 * i + 2] >> 4) | (a->coeffs[4 * i + 3] << 6);
        r[5 * i + 4] = (a->coeffs[4 * i + 3] >> 2);
    }
}

//  Unpack polynomial t1 with 10-bit coefficients. Output coefficients
//  are standard representatives.

void polyt1_unpack(poly_t *r, const uint8_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N / 4; i++) {
        r->coeffs[4 * i + 0] =
            ((a[5 * i + 0] >> 0) | ((uint32_t) a[5 * i + 1] << 8)) & 0x3FF;
        r->coeffs[4 * i + 1] =
            ((a[5 * i + 1] >> 2) | ((uint32_t) a[5 * i + 2] << 6)) & 0x3FF;
        r->coeffs[4 * i + 2] =
            ((a[5 * i + 2] >> 4) | ((uint32_t) a[5 * i + 3] << 4)) & 0x3FF;
        r->coeffs[4 * i + 3] =
            ((a[5 * i + 3] >> 6) | ((uint32_t) a[5 * i + 4] << 2)) & 0x3FF;
    }
}

//  Bit-pack polynomial t0 with coefficients in ]-2^{D-1}, 2^{D-1}].

void polyt0_pack(uint8_t *r, const poly_t *a)
{
    unsigned int i;
    uint32_t t[8];

    for (i = 0; i < MLDSA_PAR_N / 8; i++) {
        t[0] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 0];
        t[1] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 1];
        t[2] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 2];
        t[3] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 3];
        t[4] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 4];
        t[5] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 5];
        t[6] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 6];
        t[7] = (1 << (MLDSA_PAR_D - 1)) - a->coeffs[8 * i + 7];

        r[13 * i + 0] = t[0];
        r[13 * i + 1] = t[0] >> 8;
        r[13 * i + 1] |= t[1] << 5;
        r[13 * i + 2] = t[1] >> 3;
        r[13 * i + 3] = t[1] >> 11;
        r[13 * i + 3] |= t[2] << 2;
        r[13 * i + 4] = t[2] >> 6;
        r[13 * i + 4] |= t[3] << 7;
        r[13 * i + 5] = t[3] >> 1;
        r[13 * i + 6] = t[3] >> 9;
        r[13 * i + 6] |= t[4] << 4;
        r[13 * i + 7] = t[4] >> 4;
        r[13 * i + 8] = t[4] >> 12;
        r[13 * i + 8] |= t[5] << 1;
        r[13 * i + 9] = t[5] >> 7;
        r[13 * i + 9] |= t[6] << 6;
        r[13 * i + 10] = t[6] >> 2;
        r[13 * i + 11] = t[6] >> 10;
        r[13 * i + 11] |= t[7] << 3;
        r[13 * i + 12] = t[7] >> 5;
    }
}

//  Unpack polynomial t0 with coefficients in ]-2^{D-1}, 2^{D-1}].

void polyt0_unpack(poly_t *r, const uint8_t *a)
{
    unsigned int i;

    for (i = 0; i < MLDSA_PAR_N / 8; i++) {
        r->coeffs[8 * i + 0] = a[13 * i + 0];
        r->coeffs[8 * i + 0] |= (uint32_t) a[13 * i + 1] << 8;
        r->coeffs[8 * i + 0] &= 0x1FFF;

        r->coeffs[8 * i + 1] = a[13 * i + 1] >> 5;
        r->coeffs[8 * i + 1] |= (uint32_t) a[13 * i + 2] << 3;
        r->coeffs[8 * i + 1] |= (uint32_t) a[13 * i + 3] << 11;
        r->coeffs[8 * i + 1] &= 0x1FFF;

        r->coeffs[8 * i + 2] = a[13 * i + 3] >> 2;
        r->coeffs[8 * i + 2] |= (uint32_t) a[13 * i + 4] << 6;
        r->coeffs[8 * i + 2] &= 0x1FFF;

        r->coeffs[8 * i + 3] = a[13 * i + 4] >> 7;
        r->coeffs[8 * i + 3] |= (uint32_t) a[13 * i + 5] << 1;
        r->coeffs[8 * i + 3] |= (uint32_t) a[13 * i + 6] << 9;
        r->coeffs[8 * i + 3] &= 0x1FFF;

        r->coeffs[8 * i + 4] = a[13 * i + 6] >> 4;
        r->coeffs[8 * i + 4] |= (uint32_t) a[13 * i + 7] << 4;
        r->coeffs[8 * i + 4] |= (uint32_t) a[13 * i + 8] << 12;
        r->coeffs[8 * i + 4] &= 0x1FFF;

        r->coeffs[8 * i + 5] = a[13 * i + 8] >> 1;
        r->coeffs[8 * i + 5] |= (uint32_t) a[13 * i + 9] << 7;
        r->coeffs[8 * i + 5] &= 0x1FFF;

        r->coeffs[8 * i + 6] = a[13 * i + 9] >> 6;
        r->coeffs[8 * i + 6] |= (uint32_t) a[13 * i + 10] << 2;
        r->coeffs[8 * i + 6] |= (uint32_t) a[13 * i + 11] << 10;
        r->coeffs[8 * i + 6] &= 0x1FFF;

        r->coeffs[8 * i + 7] = a[13 * i + 11] >> 3;
        r->coeffs[8 * i + 7] |= (uint32_t) a[13 * i + 12] << 5;
        r->coeffs[8 * i + 7] &= 0x1FFF;

        r->coeffs[8 * i + 0] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 0];
        r->coeffs[8 * i + 1] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 1];
        r->coeffs[8 * i + 2] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 2];
        r->coeffs[8 * i + 3] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 3];
        r->coeffs[8 * i + 4] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 4];
        r->coeffs[8 * i + 5] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 5];
        r->coeffs[8 * i + 6] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 6];
        r->coeffs[8 * i + 7] = (1 << (MLDSA_PAR_D - 1)) - r->coeffs[8 * i + 7];
    }
}

//  Bit-pack polynomial with coefficients in [-(GAMMA1 - 1), GAMMA1].

void polyz_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a)
{
    unsigned int i;
    uint32_t t[4];

    if (par->gamma1 == (1 << 17)) {
        for (i = 0; i < MLDSA_PAR_N / 4; i++) {
            t[0] = (1 << 17) - a->coeffs[4 * i + 0];
            t[1] = (1 << 17) - a->coeffs[4 * i + 1];
            t[2] = (1 << 17) - a->coeffs[4 * i + 2];
            t[3] = (1 << 17) - a->coeffs[4 * i + 3];

            r[9 * i + 0] = t[0];
            r[9 * i + 1] = t[0] >> 8;
            r[9 * i + 2] = t[0] >> 16;
            r[9 * i + 2] |= t[1] << 2;
            r[9 * i + 3] = t[1] >> 6;
            r[9 * i + 4] = t[1] >> 14;
            r[9 * i + 4] |= t[2] << 4;
            r[9 * i + 5] = t[2] >> 4;
            r[9 * i + 6] = t[2] >> 12;
            r[9 * i + 6] |= t[3] << 6;
            r[9 * i + 7] = t[3] >> 2;
            r[9 * i + 8] = t[3] >> 10;
        }
    } else if (par->gamma1 == (1 << 19)) {
        for (i = 0; i < MLDSA_PAR_N / 2; i++) {
            t[0] = (1 << 19) - a->coeffs[2 * i + 0];
            t[1] = (1 << 19) - a->coeffs[2 * i + 1];

            r[5 * i + 0] = t[0];
            r[5 * i + 1] = t[0] >> 8;
            r[5 * i + 2] = t[0] >> 16;
            r[5 * i + 2] |= t[1] << 4;
            r[5 * i + 3] = t[1] >> 4;
            r[5 * i + 4] = t[1] >> 12;
        }
    }
}

//  Unpack polynomial z with coefficients in [-(GAMMA1 - 1), GAMMA1].

void polyz_unpack(const mldsa_param_t *par, poly_t *r, const uint8_t *a)
{
    unsigned int i;

    if (par->gamma1 == (1 << 17)) {
        for (i = 0; i < MLDSA_PAR_N / 4; i++) {
            r->coeffs[4 * i + 0] = a[9 * i + 0];
            r->coeffs[4 * i + 0] |= (uint32_t) a[9 * i + 1] << 8;
            r->coeffs[4 * i + 0] |= (uint32_t) a[9 * i + 2] << 16;
            r->coeffs[4 * i + 0] &= 0x3FFFF;

            r->coeffs[4 * i + 1] = a[9 * i + 2] >> 2;
            r->coeffs[4 * i + 1] |= (uint32_t) a[9 * i + 3] << 6;
            r->coeffs[4 * i + 1] |= (uint32_t) a[9 * i + 4] << 14;
            r->coeffs[4 * i + 1] &= 0x3FFFF;

            r->coeffs[4 * i + 2] = a[9 * i + 4] >> 4;
            r->coeffs[4 * i + 2] |= (uint32_t) a[9 * i + 5] << 4;
            r->coeffs[4 * i + 2] |= (uint32_t) a[9 * i + 6] << 12;
            r->coeffs[4 * i + 2] &= 0x3FFFF;

            r->coeffs[4 * i + 3] = a[9 * i + 6] >> 6;
            r->coeffs[4 * i + 3] |= (uint32_t) a[9 * i + 7] << 2;
            r->coeffs[4 * i + 3] |= (uint32_t) a[9 * i + 8] << 10;
            r->coeffs[4 * i + 3] &= 0x3FFFF;

            r->coeffs[4 * i + 0] = (1 << 17) - r->coeffs[4 * i + 0];
            r->coeffs[4 * i + 1] = (1 << 17) - r->coeffs[4 * i + 1];
            r->coeffs[4 * i + 2] = (1 << 17) - r->coeffs[4 * i + 2];
            r->coeffs[4 * i + 3] = (1 << 17) - r->coeffs[4 * i + 3];
        }
    } else if (par->gamma1 == (1 << 19)) {

        for (i = 0; i < MLDSA_PAR_N / 2; i++) {
            r->coeffs[2 * i + 0] = a[5 * i + 0];
            r->coeffs[2 * i + 0] |= (uint32_t) a[5 * i + 1] << 8;
            r->coeffs[2 * i + 0] |= (uint32_t) a[5 * i + 2] << 16;
            r->coeffs[2 * i + 0] &= 0xFFFFF;

            r->coeffs[2 * i + 1] = a[5 * i + 2] >> 4;
            r->coeffs[2 * i + 1] |= (uint32_t) a[5 * i + 3] << 4;
            r->coeffs[2 * i + 1] |= (uint32_t) a[5 * i + 4] << 12;
            /* r->coeffs[2*i+1] &= 0xFFFFF; */

            r->coeffs[2 * i + 0] = (1 << 19) - r->coeffs[2 * i + 0];
            r->coeffs[2 * i + 1] = (1 << 19) - r->coeffs[2 * i + 1];
        }
    }
}

//  Bit-pack polynomial w1 with coefficients in [0,15] or [0,43].
//  Input coefficients are assumed to be standard representatives.

void polyw1_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a)
{
    unsigned int i;

    if (par->gamma2 == (MLDSA_PAR_Q - 1) / 88) {
        for (i = 0; i < MLDSA_PAR_N / 4; i++) {
            r[3 * i + 0] = a->coeffs[4 * i + 0];
            r[3 * i + 0] |= a->coeffs[4 * i + 1] << 6;
            r[3 * i + 1] = a->coeffs[4 * i + 1] >> 2;
            r[3 * i + 1] |= a->coeffs[4 * i + 2] << 4;
            r[3 * i + 2] = a->coeffs[4 * i + 2] >> 4;
            r[3 * i + 2] |= a->coeffs[4 * i + 3] << 2;
        }
    } else {
        // GAMMA2 == (MLDSA_PAR_Q - 1) / 32
        for (i = 0; i < MLDSA_PAR_N / 2; i++) {
            r[i] = a->coeffs[2 * i + 0] | (a->coeffs[2 * i + 1] << 4);
        }
    }
}
