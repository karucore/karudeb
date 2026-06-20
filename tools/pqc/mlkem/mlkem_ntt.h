#ifndef _MLKEM_NTT_H_
#define _MLKEM_NTT_H_

#include <stdint.h>
#include "mlkem_params.h"
#include "mlkem_poly.h"

void mlkem_poly_ntt(poly_t *r);
void mlkem_poly_invntt_tomont(poly_t *r);
void poly_basemul_montgomery(poly_t *r, const poly_t *a, const poly_t *b);
void poly_tomont(poly_t *r);
void mlkem_poly_reduce(poly_t *r);
void mlkem_poly_add(poly_t *r, const poly_t *a, const poly_t *b);
void mlkem_poly_sub(poly_t *r, const poly_t *a, const poly_t *b);

#endif
