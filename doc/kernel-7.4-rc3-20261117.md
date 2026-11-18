# Linux 7.4-rc3 VCU118 acceptance

Date: 2026-11-17, using host timestamps. The board's clock starts in 1970;
dates printed inside the raw target logs are not wall-clock evidence.

Verdict: **PASS for the lab kernel update**, completed 2026-11-17 at
09:47:47 UTC. The full `board_accept.sh` run returned 0, the supplemental
encoding sweep passed, and the final kernel log has no unexpected failure.
Vector ptrace reported 13 passes, six expected skips and no failures across
19 cases. This verdict does not include KVM guest execution or autonomous
software reboot; see the limits below.
This is a mainline release candidate, not a stable kernel release.

## Inputs

- Board: VCU118, 75 MHz, VLEN=256, 2 GiB DDR4, RVA23S64/Zvk/Keccak with
  external JTAG debug enabled.
- Linux: `7.4.0-rc3-zvk-dirty`, clang/LLD 24, upstream tag `v7.4-rc3`,
  commit `aebb7274476403040d582c61478df8f4a7bf9cd3`. The dirty suffix
  reflects the local PMU and vDSO patches, not a different upstream tag.
- Kernel Image SHA-256:
  `3b45e8528ca2d99b1a6640949cd579fcbf2ce1857b782e6804851ba6726c8843`.
- Served and ROM control DTB SHA-256:
  `d617ba564798245c27343e16c86e5d76ea65ed534cc1dfcd5044f74ab3b0cec9`.
- Supplied bitstream SHA-256:
  `0b994847163b0d471816edb2b63f1c5c94d777f9b829f48364d9521512378b22`.
  Its ROM manifest identifies the build-era karu64 revision as
  `077585e98769ab298c0f24afacfc576f7ad06c81` with uncommitted build inputs.
  The current processor checkout is not a substitute for that identity.
- Existing OpenSBI v1.8.1, U-Boot 2025.01 and NFS root were reused.
  The kernel-only update did not replace the DTB or root filesystem.
- Network: host `192.168.42.1`, board `192.168.42.10`, NFSv3/TCP root
  `192.168.42.1:/srv/nfs/karudeb`.

The handoff's frozen boot evidence is in the processor checkout at
`_build/kernel-trial-20261117/`: `boot.log`, `manifest.json`, `result.json`
and `kernel-health.log`. That original `result.json` describes the smoke
test only; it deliberately predates the extended acceptance run.
The live UART capture remains `_build/boot.log`.

Durable evidence in this repository:

- [Board acceptance](data/board-accept-20261117.txt)
- [User-only counter probe](data/counters-20261117.txt)
- [Vector ptrace TAP results](data/validate-v-ptrace-20261117.txt)
- [OpenSSL known answers](data/zvknhk-check-20261117.txt)
- [Keccak encoding conformance](data/vkeccak-encodings-20261117.txt)
- [Registered crypto and final kernel log](data/kernel-health-20261117.txt)

The processor trial directory also contains `acceptance/` with the individual
target logs and `acceptance-result.json` with the extended verdict. The
five source-fetch tests and 19 DT/staging/Kconfig checks passed again during
this acceptance session.

## Acceptance

The installed `board_accept.sh` matches this repository:
SHA-256 `490e5fd37592143dcc762af78e6ddf014ce74deaf90cd3ce781e8b3f449b9c6f`.

Run as root on the board, from `/root`:

```sh
board_accept.sh --expect-kernel 7.4.0-rc3-zvk-dirty \
  --expect-isa h,smstateen,ssstateen,sstc,svpbmt,svinval,svnapot,smcntrpmf,sscofpmf,zvkb,zvknhb,zvkned,zvkg,zvbb \
  --out /root/accept-kernel-7.4-rc3-20261117
```

| Check | Result |
|---|---|
| TFTP boot, SSH and NFS root | PASS |
| Ethernet and NFS server reachability | PASS |
| Expected kernel and advertised ISA leaves | PASS |
| KVM API, VM/vCPU creation and run-area mapping | PASS; no guest execution |
| 256 MiB DDR patterns | PASS, three write/read patterns |
| User-only cycle/instruction counters | PASS, probe ratio x1.14 |
| Zvknhk OpenSSL known answers | PASS, 17 checks with accelerated/software backends |
| `xtest` instruction vectors | PASS, 39 vectors |
| Reserved vtype (`vill_probe`) | PASS, five reserved cases and a valid control |
| Cache-window probe | PASS, fetch 4.41/4.42 and load 14.07/14.23 cycles |
| Vector ptrace/syscall-state selftests | PASS, 13 passed, 6 expected skips, 0 failures |
| Scalar floating-point probe | PASS; informational latency measurements below |
| Registered kernel AES selftests | PASS, seven implementations |
| Keccak encoding conformance | PASS, 20/20: 7 legal and 13 reserved encodings |
| Post-acceptance kernel health | PASS; only expected test-induced SIGILL reports |

`validate_v_ptrace` was not installed in the image. It was cross-built
statically with GCC 14.2.0 (`-march=rv64gcv -mabi=lp64d`) from the exact
7.4-rc3 sources and exported UAPI headers, then
placed in the acceptance output directory and linked from
`/root/selftests/riscv/vector/validate_v_ptrace` so the suite can find it.
The new source contains 19 cases rather than the earlier six-case suite.
The raw TAP totals are authoritative: `pass:13 fail:0 skip:6 error:0`.
The skipped cases are inapplicable to standard RVV or this VLEN. The
board script prints "19 cases" because its `grep '^ok'` also counts TAP
`ok ... # SKIP` lines; that does not mean 19 executed passes. In particular,
the not-enabled, early-debug and syscall-clobbering cases all executed and
passed.
Binary SHA-256:
`8320a6ad86efa46ede671fda779068d4fad5266ead3fbd331d297d3973a91447`.

The informational dependent-operation latencies were 67.010 cycles for
`fmadd.d`, 63.068 for `fmul.d`, 7.429 for `fadd.d`, and 13.221 for `fmadd.s`.
These are close to the previous bitstream measurements, not a controlled
kernel A/B performance comparison.

The live ISA now includes `b` in its base string and `smcntrpmf` in its
extension list. The older 7.2.6 acceptance log did not report either token;
the DTB hash remains unchanged. These are kernel feature-discovery changes,
not newly enabled RTL features.

The seven AES registrations are `aes`, `cmac(aes)`, `ecb(aes)`, `cbc(aes)`,
`cts(cbc(aes))`, `ctr(aes)` and `xts(aes)`, backed by the `*-aes-lib`/`aes-lib`
drivers. All report `selftest : passed`. This validates their registered
selftests, not exhaustive coverage of every runtime SIMD/fallback branch
or an AES performance improvement. OpenSSL's independent userspace paths
are tested separately.

The final kernel-log check found no BUG, oops, panic, CPU warning, RCU stall,
lockup or crypto self-test failure. It contains 13 `edge_probe0` SIGILL
reports with register dumps: each is the intended result of executing a
reserved encoding, and all 13 are matched to passing encoding cases. They
are userspace signal reports, not kernel crashes.

## Limits And Reset

- KVM initialization and API creation do not establish that a guest boots.
  No guest execution, Docker workload or full ISA certification is claimed.
- No full TestFloat sweep or complete PQC benchmark/KAT matrix is claimed
  by the board-acceptance script.
- Linux software reboot shut down userspace but did not restart from ROM.
  OpenSBI reports no platform reboot device. The handoff records a
  debug-module reset-halt/resume with EBREAK controls cleared, without
  reprogramming the FPGA. This is a platform limitation, not a successful
  autonomous software reboot test. This acceptance run does not reset the
  board or attach a debugger.
- Boot reports `Kernel memory protection not selected by kernel config`.
  Successful lab acceptance is not a production-hardening verdict.
- Rollback kernel: `/srv/tftp/Image.before-7.4-rc3`. Preserve the existing
  ROM-matched `board.dtb` when switching kernels.
