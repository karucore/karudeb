//  mldsa_params.h

#ifndef _MLDSA_PARAMS_H_
#define _MLDSA_PARAMS_H_

#include <stddef.h>

#define DILITHIUM_NAMESPACE(s) mldsa_int_##s

//  dynamic paramter sets
typedef struct {
    const char *name;
    unsigned level, k, ell, eta, tau, beta, gamma1, gamma2, omega;
    size_t cp_sz, pzp_sz, w1p_sz, eta_sz;
    size_t sk_sz, pk_sz, sig_sz;
} mldsa_param_t;

//  global static parameters
#define MLDSA_SEED_SZ 32
#define MLDSA_CRH_SZ 64
#define MLDSA_TR_SZ 64
#define MLDSA_RND_SZ 32
#define MLDSA_PAR_N 256
#define MLDSA_PAR_Q 8380417
#define MLDSA_PAR_D 13
#define MLDSA_PAR_QINV 58728449

//  static sizes
#define MLDSA_POLY_T1_SZ 320
#define MLDSA_POLY_T0_SZ 416

//  maximum bytes sizes for buffers
#define MLDSA_MAX_PAR_K 8
#define MLDSA_MAX_PAR_ELL 7
#define MLDSA_MAX_CP_SZ 64
#define MLDSA_MAX_W1P_SZ 192
#define MLDSA_MAX_PZP_SZ 640

//  max key and signature sies
#define MLDSA_MAX_SK_SZ 4896
#define MLDSA_MAX_PK_SZ 2592
#define MLDSA_MAX_SIG_SZ 4627

#endif
