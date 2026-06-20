//  mlkem_params.h

#ifndef _MLKEM_PARAMS_H
#define _MLKEM_PARAMS_H

#include <stdint.h>
#include <stddef.h>

//  parameter set definition structure

typedef struct {
    const char *name;       //  Canonical name in ASCII: ML-KEM-X
    unsigned    level;      //  PQ Security Category 1..5
    unsigned    k;          //  module dimenson
    unsigned    eta1;       //  Distribution eta_1
    unsigned    du, dv;     //  Bit-dropping/scaling constants
    size_t      ek_sz;      //  encryption key size in bytes
    size_t      dk_sz;      //  decryption key size in bytes
    size_t      ct_sz;      //  ciphertext size in bytes
} mlkem_param_t;

//  static parameters
#define MLKEM_PAR_N     256
#define MLKEM_PAR_Q     3329
#define MLKEM_PAR_ETA2  2
#define MLKEM_SYM_SZ    32
#define MLKEM_SS_SZ     32
#define MLKEM_MSG_SZ    32
#define MLKEM_POLY_SZ   384

//  upper limits for static buffers
#define MLKEM_MAX_PAR_K     4
#define MLKEM_MAX_PAR_ETA1  3
#define MLKEM_MAX_EK_SZ     1568
#define MLKEM_MAX_DK_SZ     3168
#define MLKEM_MAX_CT_SZ     1568

#endif
