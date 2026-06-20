//  test_kyber.c
//  2024-07-22  Markku-Juhani O. Saarinen <mjos@iki.fi> See LICENSE.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mlkem.h"
#include "fips202.h"
#include "../plat_local.h"
#include "../my_dbg.h"

#include "mlkem_ntt.h"
#include "mlkem_poly.h"

static int hex_digit(int ch)
{
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    return -1;
}

size_t parse_hex(uint8_t *buf, size_t buf_sz, const char *s)
{
    int ch, a, b;
    size_t i, j;

    j = 0;
    b = -1;
    for (i = 0; s[i] != 0 && j < buf_sz; i++) {
        ch = s[i];
        if (ch == ' ' || ch == '\t' || ch == '\n')
            continue;
        a = hex_digit(ch);
        if (a < 0)
            break;
        if (b >= 0) {
            buf[j++] = (b << 4) + a;
            b = -1;
        } else {
            b = a;
        }
    }
    return j;
}

int print_hex(int id, const char *lab, const uint8_t *data, size_t data_sz)
{
    size_t i;
    printf("%d %s: ", id, lab);

    for (i = 0; i < data_sz; i++) {
        printf("%02X", data[i]);
    }
    printf("\n");
    return 0;
}

//  ( yes, this is an extremely fragile way of doing this, sorry )

#define KATF_BUF_READVAR(VAR, LAB, SIZ)                               \
    if (fscanf(katf, "%d " LAB " %s\n", &no, buf) != 2 || no != id || \
        parse_hex(VAR, sizeof(VAR), buf) != (SIZ))                    \
        continue;

int read_kat(FILE *katf)
{
    int keygen = 0;
    int encaps = 0;
    int decaps = 0;

    int id = 0, no = -1;
    char var[16] = "", alg[16] = "";
    char buf[0x10000];

    uint8_t ek[MLKEM_MAX_EK_SZ];
    uint8_t dk[MLKEM_MAX_DK_SZ];
    uint8_t ct[MLKEM_MAX_CT_SZ];
    uint8_t rd[32], rz[32], rm[32], kk[32];

    uint8_t ek1[MLKEM_MAX_EK_SZ];
    uint8_t dk1[MLKEM_MAX_DK_SZ];
    uint8_t ct1[MLKEM_MAX_CT_SZ];
    uint8_t kk1[32];

    const mlkem_param_t *par = NULL;
    int i, iut_n;

    int iut_pass[MLKEM_PARAMS] = {0};
    int iut_fail[MLKEM_PARAMS] = {0};

    while (fgets(buf, sizeof(buf) - 1, katf) != NULL) {
        if (sscanf(buf, "%d %15s %15s\n", &id, var, alg) != 3)
            continue;

        par = NULL;
        for (i = 0; i < MLKEM_PARAMS; i++) {
            if (strcmp(alg, mlkem_par[i]->name) == 0) {
                par = mlkem_par[i];
                iut_n = i;
                break;
            }
        }
        if (par == NULL)
            continue;

        if (strcmp(var, "keygen") == 0) {

            KATF_BUF_READVAR(rd, "d", 32);
            KATF_BUF_READVAR(rz, "z", 32);
            KATF_BUF_READVAR(ek, "ek", par->ek_sz);
            KATF_BUF_READVAR(dk, "dk", par->dk_sz);

            mlkem_keygen_internal(par, ek1, dk1, rd, rz);

            if (memcmp(ek, ek1, sizeof(ek)) != 0 ||
                memcmp(dk, dk1, sizeof(dk)) != 0) {
                printf("%s | FAIL keygen %d\n", par->name, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            keygen++;
            continue;
        }

        if (strcmp(var, "encaps") == 0) {

            KATF_BUF_READVAR(ek, "ek", par->ek_sz);
            KATF_BUF_READVAR(rm, "m", 32);
            KATF_BUF_READVAR(kk, "K", 32);
            KATF_BUF_READVAR(ct, "c", par->ct_sz);

            mlkem_encaps_internal(par, kk1, ct1, ek, rm);

            if (memcmp(kk, kk1, sizeof(kk)) != 0 ||
                memcmp(ct, ct1, sizeof(ct)) != 0) {
                printf("%s | FAIL encaps %d\n", par->name, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            encaps++;
            continue;
        }

        if (strcmp(var, "decaps") == 0) {

            KATF_BUF_READVAR(dk, "dk", par->dk_sz);
            KATF_BUF_READVAR(ct, "c", par->ct_sz);
            KATF_BUF_READVAR(kk, "K", 32);

            mlkem_decaps_internal(par, kk1, dk, ct);

            if (memcmp(kk, kk1, sizeof(kk)) != 0) {
                printf("%s | FAIL decaps %d\n", par->name, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            decaps++;
            continue;
        }
    }

    int fail = 0;
    for (i = 0; i < MLKEM_PARAMS; i++) {
        printf("%s  PASS= %d  FAIL= %d\n", mlkem_par[i]->name, iut_pass[i],
               iut_fail[i]);
        fail += iut_fail[i];
    }

    printf("keygen= %d  encaps= %d  decaps= %d\n", keygen, encaps, decaps);

    return fail;
}

#undef KATF_BUF_READVAR

int64_t poly_chksum(poly_t *v)
{
    int i;
    int64_t x;

    x = 0;
    for (i = 0; i < 256; i++) {
        x = (x * 1001 + v->coeffs[i]) % MLKEM_PAR_Q;
    }
    if (x < 0) {
        x += MLKEM_PAR_Q;
    }
    return x;
}

int64_t bench_ntt(int64_t iter)
{
    int64_t i, ic, cc;
    poly_t v;

    for (i = 0; i < 256; i++) {
        v.coeffs[i] = i;
    }
    mlkem_poly_ntt(&v);

    ic = plat_get_instret();
    cc = plat_get_cycle();
    for (i = 0; i < iter; i++) {
        mlkem_poly_ntt(&v);
    }
    cc = plat_get_cycle() - cc;
    ic = plat_get_instret() - ic;

    printf("%10ld%10ld  mlkem_poly_ntt() %ld\n",
        cc / iter, ic / iter, poly_chksum(&v));

    //  --

    for (i = 0; i < 256; i++) {
        v.coeffs[i] = i;
    }
    mlkem_poly_invntt_tomont(&v);

    ic = plat_get_instret();
    cc = plat_get_cycle();
    for (i = 0; i < iter; i++) {
        mlkem_poly_invntt_tomont(&v);
    }
    cc = plat_get_cycle() - cc;
    ic = plat_get_instret() - ic;

    printf("%10ld%10ld  mlkem_poly_invntt_tomont() %ld\n",
        cc / iter, ic / iter, poly_chksum(&v));

    return 0;
}

int64_t bench_k1600(int64_t iter)
{
    int64_t i, x, ic, cc;
    uint64_t st[25];

    for (i = 0; i < 25; i++) {
        st[i] = i;
    }
    KeccakF1600_StatePermute(st);

    ic = plat_get_instret();
    cc = plat_get_cycle();
    for (i = 0; i < iter; i++) {
        KeccakF1600_StatePermute(st);
    }
    cc = plat_get_cycle() - cc;
    ic = plat_get_instret() - ic;

    x = 0;
    for (i = 0; i < 25; i++) {
        x ^= st[i];
    }
    printf("%10ld%10ld  KeccakF1600_StatePermute()  %016lx\n",
           cc / iter, ic / iter, x);

    return x;
}

int do_bench(const mlkem_param_t *par, int64_t iter)
{
    uint8_t pk[MLKEM_MAX_EK_SZ];
    uint8_t sk[MLKEM_MAX_DK_SZ];
    uint8_t ct[MLKEM_MAX_CT_SZ];
    uint8_t key_a[MLKEM_SS_SZ];
    uint8_t key_b[MLKEM_SS_SZ];

    uint8_t seed[MLKEM_SYM_SZ];

    //  "excercise the functions"
    memset(seed, 0, sizeof(seed));
    mlkem_keygen_internal(par, pk, sk, seed, seed);
    mlkem_encaps_internal(par, key_b, ct, pk, seed);
    mlkem_decaps_internal(par, key_a, sk, ct);

    //  benchmarking
    int64_t i;
    int64_t cc, ckg = 0, cenc = 0, cdec = 0;
    int64_t ic, ikg = 0, ienc = 0, idec = 0;
    int64_t fkg = 0, fenc = 0, fdec = 0;

    for (i = 0; i < iter; i++) {

        ((int64_t *) seed)[0] ^= i;

        //  Keypair generation
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        mlkem_keygen_internal(par, pk, sk, seed, seed);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        ckg += cc;
        ikg += ic;
        fkg += KeccakF1600_count;

        //  Encapsulation
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        mlkem_encaps_internal(par, key_b, ct, pk, seed);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        cenc += cc;
        ienc += ic;
        fenc += KeccakF1600_count;

        //  Decapsulation
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        mlkem_decaps_internal(par, key_a, sk, ct);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        cdec += cc;
        idec += ic;
        fdec += KeccakF1600_count;

        //  make it inter-dependent
        memcpy(seed, key_a, 32);
    }

    printf("%12s              cycles     insns   f1600  iter= %ld\n",
            par->name, iter);
    printf("%12s  KeyGen  %10ld%10ld  %6.2f  mlkem_keygen_internal()\n",
            par->name, ckg / iter, ikg / iter,
            ((double) fkg) / ((double) iter));
    printf("%12s  Encaps  %10ld%10ld  %6.2f  mlkem_encaps_internal()\n",
            par->name, cenc / iter, ienc / iter,
            ((double) fenc) / ((double) iter));
    printf("%12s  Decaps  %10ld%10ld  %6.2f  mlkem_decaps_internal()\n",
            par->name, cdec / iter, idec / iter,
            ((double) fdec) / ((double) iter));

    return 0;
}

int main(int argc, char **argv)
{
    int fail = 0;
    FILE *katf;

    if (argc <= 1) {
        printf("%10s%10s\n", "cycles", "insns");
        bench_ntt(1000);
        bench_k1600(1000);
        for (int i = 0; i < MLKEM_PARAMS; i++) {
            fail += do_bench(mlkem_par[i], 100);
        }
        return fail;
    }

    katf = fopen(argv[1], "r");
    if (katf == NULL) {
        perror(argv[1]);
        return -1;
    }
    fail = read_kat(katf);
    fclose(katf);

    return fail;
}
