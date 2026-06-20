//  mlkem_kpke.h

#ifndef _MLKEM_KPKE_H_
#define _MLKEM_KPKE_H_

#include <stdint.h>
#include "mlkem_params.h"
#include "polyvec.h"

void kpke_keygen(const mlkem_param_t *par, uint8_t *ek, uint8_t *dk,
                 const uint8_t d[MLKEM_SYM_SZ]);

void kpke_encrypt(const mlkem_param_t *par, uint8_t *c,
                  const uint8_t *ek, const uint8_t m[MLKEM_MSG_SZ],
                  const uint8_t r[MLKEM_SYM_SZ]);

void kpke_decrypt(const mlkem_param_t *par, uint8_t m[MLKEM_MSG_SZ],
                  const uint8_t *dk, const uint8_t *c);

#endif
