#include <openssl/aes.h>
#include <openssl/evp.h>
#include <openssl/modes.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char zero_key[16] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static const unsigned char zero_iv[12] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static const unsigned char zero_pt[16] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static const unsigned char nist_gcm_ct[16] = {
    0x03, 0x88, 0xda, 0xce, 0x60, 0xb6, 0xa3, 0x92,
    0xf3, 0x28, 0xc2, 0xb9, 0x71, 0xb2, 0xfe, 0x78,
};

static const unsigned char nist_gcm_tag[16] = {
    0xab, 0x6e, 0x47, 0xd4, 0x2c, 0xec, 0x13, 0xbd,
    0xf5, 0x3a, 0x67, 0xb2, 0x12, 0x57, 0xbd, 0xdf,
};

static void print_hex(const unsigned char *buf, size_t len)
{
    for (size_t i = 0; i < len; i++)
        printf("%02x", buf[i]);
}

static int print_result(const unsigned char *ct, const unsigned char *tag)
{
    print_hex(ct, sizeof(nist_gcm_ct));
    putchar(':');
    print_hex(tag, sizeof(nist_gcm_tag));
    putchar('\n');

    return memcmp(ct, nist_gcm_ct, sizeof(nist_gcm_ct)) != 0 ||
           memcmp(tag, nist_gcm_tag, sizeof(nist_gcm_tag)) != 0;
}

static int run_evp_gcm_zero(void)
{
    EVP_CIPHER_CTX *ctx = NULL;
    unsigned char ct[sizeof(zero_pt)];
    unsigned char tag[16];
    int out_len = 0;
    int total = 0;
    int rc = 1;

    memset(ct, 0, sizeof(ct));
    memset(tag, 0, sizeof(tag));

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL)
        goto out;

    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) != 1)
        goto out;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, sizeof(zero_iv), NULL) != 1)
        goto out;
    if (EVP_EncryptInit_ex(ctx, NULL, NULL, zero_key, zero_iv) != 1)
        goto out;
    if (EVP_EncryptUpdate(ctx, ct, &out_len, zero_pt, sizeof(zero_pt)) != 1)
        goto out;
    total = out_len;
    if (EVP_EncryptFinal_ex(ctx, ct + total, &out_len) != 1)
        goto out;
    total += out_len;
    if (total != (int)sizeof(ct))
        goto out;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, sizeof(tag), tag) != 1)
        goto out;

    rc = print_result(ct, tag);

out:
    EVP_CIPHER_CTX_free(ctx);
    return rc;
}

static int run_gcm128_zero(void)
{
    AES_KEY aes_key;
    GCM128_CONTEXT *ctx = NULL;
    unsigned char ct[sizeof(zero_pt)];
    unsigned char tag[16];
    int rc = 1;

    memset(ct, 0, sizeof(ct));
    memset(tag, 0, sizeof(tag));

    if (AES_set_encrypt_key(zero_key, 128, &aes_key) != 0)
        goto out;

    ctx = CRYPTO_gcm128_new(&aes_key, (block128_f)AES_encrypt);
    if (ctx == NULL)
        goto out;

    CRYPTO_gcm128_setiv(ctx, zero_iv, sizeof(zero_iv));
    if (CRYPTO_gcm128_encrypt(ctx, zero_pt, ct, sizeof(zero_pt)) != 0)
        goto out;
    CRYPTO_gcm128_tag(ctx, tag, sizeof(tag));

    rc = print_result(ct, tag);

out:
    if (ctx != NULL)
        CRYPTO_gcm128_release(ctx);
    return rc;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "Usage: %s {gcm-evp-zero|ghash-gcm128-zero}\n", argv0);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        usage(argv[0]);
        return 2;
    }

    if (strcmp(argv[1], "gcm-evp-zero") == 0)
        return run_evp_gcm_zero();
    if (strcmp(argv[1], "ghash-gcm128-zero") == 0)
        return run_gcm128_zero();

    usage(argv[0]);
    return 2;
}
