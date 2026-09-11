#ifndef _MLDSA_NTT_H_
#define _MLDSA_NTT_H_

#include <stdint.h>
#include "mldsa_params.h"

void mldsa_ntt(int32_t a[MLDSA_PAR_N]);
void mldsa_invntt(int32_t a[MLDSA_PAR_N]);

#endif
