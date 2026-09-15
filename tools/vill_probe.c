#include <stdio.h>
#include <stdint.h>
// vill_probe.c -- vsetvl with illegal vtype must set vill=1 and vl=0 (RVV 1.0).
// Regression for the karu64 finding of 2026-09-14: a requested vtype with only
// bit 63 (vill) set was accepted as a valid e8,m1 instead of being rejected.
// Linux relies on that exact encoding to discard vector state on syscalls.
/* Direct probe of vsetvl with an illegal vtype, no kernel involvement. Per the
 * RVV 1.0 spec (vsetvl* with unsupported vtype): vill=1, vl=0, other vtype
 * bits zero. */
static int fails;
static void probe(const char *label, uint64_t vtype_req, int expect_illegal)
{
    uint64_t vl, vtype, vlr;
    asm volatile(".option push\n.option arch, +v\n"
                 "vsetvli %0, x0, e16, m2, tu, mu\n"   /* known-good state first */
                 ".option pop\n" : "=r"(vlr));
    asm volatile(".option push\n.option arch, +v\n"
                 "vsetvl %0, x0, %2\n"
                 "csrr %1, vtype\n"
                 ".option pop\n" : "=r"(vl), "=r"(vtype) : "r"(vtype_req));
    int ok = expect_illegal ? ((vtype == (1ULL << 63)) && vl == 0)
                            : (vtype == vtype_req && vl != 0);
    if (!ok) fails++;
    printf("%-34s req vtype=%016llx -> vl=%llu vtype=%016llx  %s\n", label,
           (unsigned long long)vtype_req, (unsigned long long)vl,
           (unsigned long long)vtype,
           ok ? "ok" : (expect_illegal ? "FAIL (spec: vill=1, vl=0)" : "FAIL (valid vtype rejected)"));
}
int main(void)
{
    probe("kernel's vtype_inval (bit 63)", 1ULL << 63, 1);
    probe("vill bit plus valid low bits", (1ULL << 63) | 0x9, 1);
    probe("reserved vtype bits 8..62 set", 0x100, 1);
    probe("reserved bit 62", 1ULL << 62, 1);
    probe("vsew=e128 (3<<3 => reserved)", 0x38, 1);       /* vsew=111 reserved */
    probe("valid e16,m2 (control)", 0x9, 0);
    printf("vill_probe: %s\n", fails ? "FAIL" : "PASS");
    return fails != 0;
}
