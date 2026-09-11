//  cbd.h

#ifndef _CBD_H_
#define _CBD_H_

#include <stdint.h>
#include "mlkem_params.h"
#include "mlkem_poly.h"

void poly_cbd_eta1(const mlkem_param_t *par, poly_t *r, const uint8_t *buf);
void poly_cbd_eta2(poly_t *r, const uint8_t *buf);

#endif
