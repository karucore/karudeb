#ifndef _REDUCE_H_
#define _REDUCE_H_

#include <stdint.h>
#include "mlkem_params.h"

#define MLKEM_PAR_MONT -1044  // 2^16 mod q
#define MLKEM_PAR_QINV -3327  // q^-1 mod 2^16

//  Montgomery reduction; given a 32-bit integer a, computes
//  16-bit integer congruent to a * R^-1 mod q, where R=2^16

static inline int16_t montgomery_reduce(int32_t a)
{
    int16_t t;

    t = (int16_t) a * MLKEM_PAR_QINV;
    t = (a - (int32_t) t * MLKEM_PAR_Q) >> 16;
    return t;
}

//  Barrett reduction; given a 16-bit integer a, computes centered
//  representative congruent to a mod q in {-(q-1)/2,...,(q-1)/2}

static inline int16_t barrett_reduce(int16_t a)
{
    int16_t t;
    const int16_t v = ((1 << 26) + MLKEM_PAR_Q / 2) / MLKEM_PAR_Q;

    t = ((int32_t) v * a + (1 << 25)) >> 26;
    t *= MLKEM_PAR_Q;
    return a - t;
}

//  Multiplication followed by Montgomery reduction

static inline int16_t fqmul(int16_t a, int16_t b)
{
    return montgomery_reduce((int32_t) a * b);
}

//  Multiplication of polynomials in Zq[X]/(X^2-zeta)
//  used for multiplication of elements in Rq in NTT domain

static inline void basemul( int16_t r[2],
                            const int16_t a[2], const int16_t b[2],
                            int16_t zeta)
{
    r[0] = fqmul(a[1], b[1]);
    r[0] = fqmul(r[0], zeta);
    r[0] += fqmul(a[0], b[0]);
    r[1] = fqmul(a[0], b[1]);
    r[1] += fqmul(a[1], b[0]);
}

#endif
