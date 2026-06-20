//  test_dilithium.c

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "fips202.h"
#include "mldsa_params.h"
#include "mldsa.h"
#include "mldsa_ntt.h"

#include "../my_dbg.h"
#include "../plat_local.h"

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

#define KATF_BUF_READ(LAB)                                          \
    if (fscanf(katf, "%d " LAB " %s\n", &no, buf) != 2 || no != id) \
        continue;

#define KATF_BUF_PARSE(VAR) parse_hex(VAR, sizeof(VAR), buf)
/*
#define KATF_BUF_READVAR(VAR, LAB)          \
    KATF_BUF_READ(LAB);                     \
    if (KATF_BUF_PARSE(VAR) != sizeof(VAR)) \
        continue;
*/
#define KATF_BUF_READVAR(VAR, LAB, SIZ) \
    KATF_BUF_READ(LAB);                 \
    if (KATF_BUF_PARSE(VAR) != (SIZ))   \
        continue;

int read_kat(FILE *katf)
{
    int keygen = 0;
    int siggen = 0;
    int sigver = 0;

    int id = 0, no = -1;
    char var[16] = "", alg[16] = "";
    uint8_t xi[32], rnd[32];
    uint8_t pk[MLDSA_MAX_PK_SZ];
    uint8_t sk[MLDSA_MAX_SK_SZ];

    char buf[0x10000];
    uint8_t mp[0x8000];
    size_t mp_sz, sig_sz = 0;

    uint8_t pk1[MLDSA_MAX_PK_SZ];
    uint8_t sk1[MLDSA_MAX_SK_SZ];
    uint8_t sig[MLDSA_MAX_SIG_SZ];
    uint8_t sig1[MLDSA_MAX_SIG_SZ];

    int res = 0, res1 = 0;

    const mldsa_param_t *par = NULL;
    int i, iut_n = 0;

    int iut_pass[MLDSA_PARAMS] = {0};
    int iut_fail[MLDSA_PARAMS] = {0};

    while (fgets(buf, sizeof(buf) - 1, katf) != NULL) {

        if (sscanf(buf, "%d %15s %15s\n", &id, var, alg) != 3)
            continue;

        par = NULL;
        for (i = 0; i < 3; i++) {
            if (strcmp(alg, mldsa_par[i]->name) == 0) {
                par = mldsa_par[i];
                iut_n = i;
                break;
            }
        }
        if (par == NULL)
            continue;

        if (strcmp(var, "keygen") == 0) {
            KATF_BUF_READVAR(xi, "xi", sizeof(xi));
            KATF_BUF_READVAR(pk, "pk", par->pk_sz);
            KATF_BUF_READVAR(sk, "sk", par->sk_sz);

            mldsa_keygen_internal(par, pk1, sk1, xi);

            if (memcmp(pk, pk1, par->pk_sz) != 0 ||
                memcmp(sk, sk1, par->sk_sz) != 0) {
                printf("%s | FAIL keygen %d\n", alg, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            keygen++;
            continue;
        }

        if (strcmp(var, "siggen") == 0) {
            KATF_BUF_READVAR(sk, "sk", par->sk_sz);
            KATF_BUF_READ("mp");
            mp_sz = KATF_BUF_PARSE(mp);
            KATF_BUF_READVAR(rnd, "rnd", sizeof(rnd));
            KATF_BUF_READVAR(sig, "sig", par->sig_sz);

            sig_sz = 0;
            if (mldsa_sign_internal(par, sig1, &sig_sz, sk, mp, mp_sz, rnd) ||
                sig_sz != par->sig_sz)
                continue;

            if (memcmp(sig, sig1, par->sig_sz) != 0) {
                printf("%s | FAIL siggen %d\n", alg, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            siggen++;
            continue;
        }

        if (strcmp(var, "sigver") == 0) {
            KATF_BUF_READVAR(pk, "pk", par->pk_sz);
            KATF_BUF_READ("mp");
            mp_sz = KATF_BUF_PARSE(mp);
            KATF_BUF_READVAR(sig, "sig", par->sig_sz);
            KATF_BUF_READ("res");
            res = buf[0] == '1';
            res1 = mldsa_verify_internal(par, pk, mp, mp_sz, sig, par->sig_sz);

            if (res != res1) {
                printf("%s | FAIL sigver %d\n", alg, id);
                iut_fail[iut_n]++;
            } else {
                iut_pass[iut_n]++;
            }

            sigver++;
            continue;
        }
    }

    int fail = 0;
    for (i = 0; i < MLDSA_PARAMS; i++) {
        printf("%s  PASS= %d  FAIL= %d\n", mldsa_par[i]->name, iut_pass[i],
               iut_fail[i]);
        fail += iut_fail[i];
    }

    printf("keygen= %d  siggen= %d  sigver= %d\n", keygen, siggen, sigver);

    return fail;
}

#undef KATF_BUF_READ
#undef KATF_BUF_PARSE
#undef KATF_BUF_READVAR

//  ===

int64_t poly_chksum(poly_t *v)
{
    int i;
    int64_t x;

    x = 0;
    for (i = 0; i < 256; i++) {
        x = (x * 1000001 + v->coeffs[i]) % MLDSA_PAR_Q;
    }
    if (x < 0) {
        x += MLDSA_PAR_Q;
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
    mldsa_poly_ntt(&v);

    ic = plat_get_instret();
    cc = plat_get_cycle();
    for (i = 0; i < iter; i++) {
        mldsa_poly_ntt(&v);
    }
    cc = plat_get_cycle() - cc;
    ic = plat_get_instret() - ic;

    printf("%10ld%10ld  mldsa_poly_ntt() %ld\n",
        cc / iter, ic / iter, poly_chksum(&v));

    //  --

    for (i = 0; i < 256; i++) {
        v.coeffs[i] = i;
    }
    mldsa_poly_invntt_tomont(&v);

    ic = plat_get_instret();
    cc = plat_get_cycle();
    for (i = 0; i < iter; i++) {
        mldsa_poly_invntt_tomont(&v);
    }
    cc = plat_get_cycle() - cc;
    ic = plat_get_instret() - ic;

    printf("%10ld%10ld  mldsa_poly_invntt_tomont() %ld\n",
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

#define MLEN 4

int do_bench(const mldsa_param_t *par, int64_t iter)
{
    int fail = 0;
    uint8_t pk[MLDSA_MAX_PK_SZ] = {0};
    uint8_t sk[MLDSA_MAX_SK_SZ] = {0};
    uint8_t sig[MLDSA_MAX_SIG_SZ] = {0};
    uint8_t m[MLEN] = {0};
    size_t siglen = 0;

    uint8_t seed[32], rnd[32];

    memset(seed, 0x00, 32);
    memset(rnd, 0x00, 32);

    //  "exercise" the routines
    mldsa_keygen_internal(par, pk, sk, seed);
    mldsa_sign_internal(par, sig, &siglen, sk, m, MLEN, rnd);
    if (!mldsa_verify_internal(par, pk, m, MLEN, sig, siglen)) {
        fprintf(stderr, "Signature verification failed!\n");
        return 1;
    }
    m[0]++;
    if (mldsa_verify_internal(par, pk, m, MLEN, sig, siglen)) {
        fprintf(stderr, "Signature verification -- false positive!\n");
        return 1;
    }

    //  benchmarking
    int r = 0;
    int64_t i;
    int64_t cc, ckg = 0, csgn = 0, cvfy = 0;
    int64_t ic, ikg = 0, isgn = 0, ivfy = 0;
    int64_t     fkg = 0, fsgn = 0, fvfy = 0;

    for (i = 0; i < iter; i++) {

        ((int64_t *) seed)[0] = i;
        ((int64_t *) rnd)[0] = i;

        //  Keypair Generation
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        mldsa_keygen_internal(par, pk, sk, seed);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        ckg += cc;
        ikg += ic;
        fkg += KeccakF1600_count;

        //  Signature
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        mldsa_sign_internal(par, sig, &siglen, sk, m, MLEN, rnd);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        csgn += cc;
        isgn += ic;
        fsgn += KeccakF1600_count;

        //  Verify
        KeccakF1600_count = 0;
        ic = plat_get_instret();
        cc = plat_get_cycle();
        r = mldsa_verify_internal(par, pk, m, MLEN, sig, siglen);
        cc = plat_get_cycle() - cc;
        ic = plat_get_instret() - ic;
        cvfy += cc;
        ivfy += ic;
        fvfy += KeccakF1600_count;

        if (!r) {
            fprintf(stderr, "Signature verification failed!\n");
            fail++;
        }
    }

    printf("%12s            cycles     insns   f1600  iter= %ld\n",
            par->name, iter);
    printf("%12s KeyGen %10ld%10ld  %6.2f  mldsa_keygen_internal()\n",
            par->name, ckg / iter, ikg / iter,
            ((double) fkg) / ((double) iter));
#ifdef MLDSA_PROFILE
    {
        extern uint64_t mldsa_profile_phase[10];
        extern const char *mldsa_profile_name[10];
        uint64_t total = 0;
        for (int p = 0; p < 10; p++) total += mldsa_profile_phase[p];
        for (int p = 0; p < 10; p++) {
            uint64_t v = mldsa_profile_phase[p] / iter;
            printf("%12s  KG.%s  %10lu  %5.1f%%\n",
                par->name, mldsa_profile_name[p], v,
                total ? 100.0 * mldsa_profile_phase[p] / total : 0.0);
            mldsa_profile_phase[p] = 0;
        }
    }
#endif
    printf("%12s Sign   %10ld%10ld  %6.2f  mldsa_sign_internal()\n",
            par->name, csgn / iter, isgn / iter,
            ((double) fsgn) / ((double) iter));
    printf("%12s Verify %10ld%10ld  %6.2f  mldsa_verify_internal()\n",
            par->name, cvfy / iter, ivfy / iter,
            ((double) fvfy) / ((double) iter));

    return fail;
}

int kek();
int kat_test();  // kat_test.c

int main(int argc, char **argv)
{
    int fail = 0;
    FILE *katf;

    if (argc <= 1) {
        printf("%10s%10s\n", "cycles", "insns");
        bench_ntt(1000);
        bench_k1600(1000);

        for (int i = 0; i < MLDSA_PARAMS; i++) {
            fail += do_bench(mldsa_par[i], 10);
        }
        return 0;
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
