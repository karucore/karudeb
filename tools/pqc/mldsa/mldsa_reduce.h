//  mldsa_reduce.h

#ifndef _MLDSA_REDUCE_H_
#define _MLDSA_REDUCE_H_

#include <stdint.h>
#include "mldsa_params.h"

// Description: For finite field element a with -2^{31}Q <= a <= Q*2^31,
//              compute r \equiv a*2^{-32} (mod Q) such that -Q < r < Q.

static inline int32_t montgomery_reduce(int64_t a)
{
    int32_t t;

    t = (int64_t) (int32_t) a * MLDSA_PAR_QINV;
    t = (a - (int64_t) t * MLDSA_PAR_Q) >> 32;
    return t;
}

// Description: For finite field element a with a <= 2^{31} - 2^{22} - 1,
//              compute r \equiv a (mod Q) such that -6283008 <= r <= 6283008.

static inline int32_t reduce32(int32_t a)
{
    int32_t t;

    t = (a + (1 << 22)) >> 23;
    t = a - t * MLDSA_PAR_Q;
    return t;
}

// Description: Add Q if input coefficient is negative.

static inline int32_t caddq(int32_t a)
{
    a += (a >> 31) & MLDSA_PAR_Q;
    return a;
}

static inline int32_t freeze(int32_t a)
{
    a = reduce32(a);
    a = caddq(a);
    return a;
}
#endif
