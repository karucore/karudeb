//  mlkem.h

#ifndef _MLKEM_H_
#define _MLKEM_H_

#include <stdint.h>
#include "mlkem_params.h"

//  number of paramter sets defined
#define MLKEM_PARAMS 3
extern const mlkem_param_t mlkem_512;
extern const mlkem_param_t mlkem_768;
extern const mlkem_param_t mlkem_1024;
extern const mlkem_param_t *mlkem_par[MLKEM_PARAMS];

//  external interface
int mlkem_keygen_internal(const mlkem_param_t *par, uint8_t *ek, uint8_t *dk,
                          const uint8_t *d, const uint8_t *z);

int mlkem_encaps_internal(const mlkem_param_t *par, uint8_t *ss, uint8_t *ct,
                          const uint8_t *ek, const uint8_t *m);

int mlkem_decaps_internal(const mlkem_param_t *par, uint8_t *kp,
                          const uint8_t *dk, const uint8_t *ct);

#endif
