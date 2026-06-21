# karudeb

Debian `riscv64` NFS-root Linux distribution scaffolding for the karu64
RV64GC/RV64GCV platform. It targets systems that boot without local mass
storage.

The default userspace is intentionally plain: Debian minbase, `sysvinit`,
`ifupdown`, serial getty, OpenSSH, and a BusyBox rescue shell.

For simple QEMU smoke tests, the preferred user-level root filesystem transport
is `virtio-9p`. QEMU itself serves the filesystem as your user, so there is no
NFS daemon, no rpcbind, no privileged ports, and no TAP requirement.

For the JWM/VNC profile, use a `virtio-blk` ext4 image. It avoids 9p
symlink/xattr corner cases and is the path tested with the RV64GCV QEMU CPU
model.

For real hardware with the Debian rootfs, use initramfs-less NFS root. The
kernel mounts the root filesystem directly over NFS, so the network driver, IP
autoconfiguration, and NFS client support must be built into the kernel.

For the reduced `rv64imac` karu64 bring-up bitstream, use the repository-local
Linux + BusyBox initramfs image described below. It consumes the same generic
karu64 OpenSBI `fw_jump` artifact as the other board boot paths; the initramfs
userspace is soft-float and does not depend on a Debian root filesystem.

When `build-rootfs.sh` runs without sudo, `mmdebstrap` uses a user namespace.
That produces a usable rootfs for inspection and tar packaging, but the on-disk
directory is shifted-owned on the host. For a real NFS export, either build with
`MMDEBSTRAP_USE_SUDO=1` or extract the packaged tarball as root into the export
directory.

For QEMU 9p, use a separate user-owned copy created from the packaged rootfs.
This is intentionally separate from the root-owned NFS export used for hardware.

## Repository layout

- `scripts/`: rootfs, kernel, QEMU, NFS export, and karu64 staging helpers.
- `configs/`: Linux fragments, device trees, BusyBox fragments, and rootfs
  config snippets.
- `configs/ssh/`: committed lab SSH client and host keys for reproducible local
  images.
- `initramfs/karu64-rv64imac/`: files copied into the reduced RV64IMAC
  initramfs image.
- `tools/`: benchmark helpers and the repo-local ML-KEM/ML-DSA sources under
  `tools/pqc/`.
- `patches/`: Linux patches applied by `scripts/build-linux.sh` when the source
  version matches.

Generated rootfs trees, kernel builds, archives, disk images, TFTP staging
trees, and QEMU logs are written under `build/` by default and are not part of
the source release.

Before committing a release tree, run:

```sh
make -n clean
bash -n scripts/*.sh
sh -n initramfs/karu64-rv64imac/init initramfs/karu64-rv64imac/udhcpc.script configs/rootfs-init-tmpfs-nosed.sh
```

The committed private keys under `configs/ssh/` are intentional lab keys. Keep
them only for reproducible local images; override or disable them for private
deployments. Git stores them as regular non-executable files; the build scripts
install the host private key and target `authorized_keys` with restrictive
permissions inside generated images.

## Host tools

Check the host first:

```sh
./scripts/check-host.sh
```

On a fresh Debian or Ubuntu host, install the tools used by the normal rootfs,
kernel, NFS, QEMU, and karu64 staging paths:

```sh
sudo apt-get update
sudo apt-get install -y \
  git sudo ca-certificates curl xz-utils zstd gzip tar coreutils \
  mmdebstrap debootstrap arch-test qemu-user qemu-user-static qemu-user-binfmt \
  qemu-system-misc nfs-kernel-server rpcbind iproute2 \
  build-essential patch clang llvm lld binutils-riscv64-linux-gnu \
  gcc-riscv64-linux-gnu bc bison flex libssl-dev libelf-dev \
  device-tree-compiler u-boot-tools \
  fakeroot e2fsprogs tigervnc-viewer python3
```

Rootfs post-configuration prefers clang for target helper builds. Set
`KARUDEB_TARGET_CC` to choose the compiler and `KARUDEB_TARGET_SYSROOT` to
choose a sysroot explicitly. If the rootfs contains target development files,
`build-rootfs.sh` uses that rootfs as the sysroot automatically.

The OpenSSL KAT helper needs target headers and link-time libraries. For the
RVA23/Zvk rootfs profile, include target development packages:

```sh
EXTRA_PACKAGES=vim-tiny,tcpdump,libc6-dev,linux-libc-dev,libssl-dev \
./scripts/build-rootfs.sh
```

Kernel builds prefer clang/LLVM when `clang`, `ld.lld`, and the LLVM binutils
are in `PATH`. Set `CROSS_COMPILE=riscv64-linux-gnu-` to force a GCC cross
compiler, or set `LLVM=1` explicitly for the kernel's LLVM build path.

For a smaller rootfs-only host, the minimum package set is:

```sh
sudo apt-get update
sudo apt-get install -y \
  git sudo ca-certificates curl xz-utils zstd gzip tar coreutils \
  mmdebstrap debootstrap arch-test qemu-user qemu-user-static qemu-user-binfmt \
  clang llvm lld binutils-riscv64-linux-gnu \
  nfs-kernel-server rpcbind iproute2 python3
```

For QEMU 9p, the ext4 JWM/VNC smoke test, or local VNC viewing, also keep:

```sh
sudo apt-get install -y qemu-system-misc fakeroot e2fsprogs tigervnc-viewer
```

On some Debian releases the user-mode RISC-V emulator is packaged as
`qemu-user-static` rather than `qemu-user`. If you use `mmdebstrap` for a
foreign-architecture rootfs, `arch-test riscv64` must report that `riscv64` is
supported. If it does not, install or enable the QEMU binfmt registration.

## Build a root filesystem

```sh
./scripts/build-rootfs.sh
```

Defaults:

- Debian suite: `trixie`
- Architecture: `riscv64`
- Output directory: `build/rootfs`
- Init: `sysvinit`
- Serial console: `ttyS0` at `115200`
- Locale: `C.UTF-8`
- Root password: `root`
- Normal lab user: `karu` with UID/GID `1000`, password `karu`, and password
  sudo access
- Serial autologin: enabled for lab bring-up
- SSH server: OpenSSH with normal `ssh`, `scp`, and `sftp`
- SSH password logins: disabled; use `authorized_keys`
- Lab SSH client key: `configs/ssh/karudeb_lab_ed25519`; its public key
  `configs/ssh/karudeb_lab_ed25519.pub` is installed as `authorized_keys` for
  both `root` and `karu`
- Lab SSH host key: `configs/ssh/karudeb_host_ed25519_key`, installed as
  `/etc/ssh/ssh_host_ed25519_key`
- Benchmark counters: direct RISC-V `rdcycle`/`rdinstret` enabled when the
  kernel exposes `kernel.perf_user_access`
- Benchmark wrapper: `/usr/local/bin/perf_run`, built from
  `tools/perf_run.c`, keeps raw cycle/instruction counters usable before
  execing a benchmark, and also has a `--user-count` mode for whole-process
  perf counts with kernel time excluded
- OpenSSL RISC-V crypto benchmark suite: `/usr/local/bin/openssl_zvk_bench`,
  installed from `tools/openssl_zvk_bench.sh`, with the
  `/usr/local/bin/openssl_zvk_kat` helper for GCM/GHASH known-answer tests
- BusyBox rescue PID1: `/usr/local/sbin/karudeb-busybox-init`
- JWM/VNC profile: disabled unless `KARUDEB_JWM_VNC=1`; when installed, the
  VNC service is manually startable but does not autostart unless
  `KARUDEB_VNC_AUTOSTART=1`

Optional JWM-over-VNC profile:

```sh
KARUDEB_JWM_VNC=1 FORCE=1 ROOTFS_DIR=build/rootfs-jwm-vnc ./scripts/build-rootfs.sh
ROOTFS_DIR=build/rootfs-jwm-vnc \
OUT=build/karudeb-riscv64-jwm-vnc-rootfs.tar.zst \
./scripts/package-rootfs.sh
```

This adds a minimal JWM/xterm session served by TigerVNC's virtual X server. It
does not require physical display hardware, a framebuffer, or a QEMU display
device.
The service is available as `karudeb-vnc`, but is not enabled at boot by
default. Use `service karudeb-vnc start` when you want a VNC session, or build
with `KARUDEB_VNC_AUTOSTART=1` to restore boot-time startup.

For benchmark images, the rootfs starts `karudeb-benchmark-counters`, which
writes `2` to `/proc/sys/kernel/perf_user_access` when that sysctl exists.
On RISC-V Linux this legacy mode permits direct userspace reads of `cycle`,
`time`, and `instret`. If a benchmark dies with `Illegal instruction` at a word
like `0xc02029f3`, that is `rdinstret` trapping because the kernel did not
enable userspace counter access.
The same service writes `0` to `/proc/sys/kernel/perf_event_paranoid` by
default so unprivileged lab users can open per-process hardware cycle and
instruction events for `/usr/local/bin/perf_run`. A stricter value may also be
usable for self/child user-space events; one validated full-vector board image
allowed the `karu` user to run `perf_run --user-count` with
`perf_event_paranoid=2`.

Raw `rdcycle`/`rdinstret` reads are direct CSR reads. They are useful for
low-overhead bracketed measurements inside a benchmark, but they count whatever
the hardware counter is currently configured to count and should be treated as
total counters by default. For a Linux-mediated user-only whole-process count,
use:

```sh
/usr/local/bin/perf_run --user-count -- ./benchmark args...
```

That path opens per-process cycle and instruction events with
`exclude_kernel=1`; on Smcntrpmf/Sscofpmf hardware, OpenSBI is responsible for
programming the privilege-mode counter filters.

Hardware sanity check from a full-vector bitstream (`7.1.1-zvk`, VLEN=256,
Zvk+Keccak, Smcntrpmf/Sscofpmf advertised in the live DTB):

```sh
/usr/local/bin/perf_run --user-count -- /bin/sleep 3
su karu -c '/usr/local/bin/perf_run --user-count -- /bin/sleep 3'
cd /home/karu
su karu -c '/usr/local/bin/perf_run --user-count -- ./xmlkem.rv64gcv_zbb'
```

The `sleep 3` runs reported about 20 million cycles and 1.7-1.9 million
instructions, far below three seconds of 75 MHz wall-clock cycles, so
kernel/idle time was excluded. The ML-KEM benchmark completed as `karu` and the
wrapper printed whole-process user counts, confirming that the
Linux perf-event -> OpenSBI -> Smcntrpmf/Sscofpmf path is usable. Separate raw
`perf_run` invocations are not a reliable global monotonic-counter test after
perf events have been opened and closed; use raw `rdcycle`/`rdinstret` inside a
single benchmark process for low-overhead bracketed measurements.

The ML-KEM and ML-DSA benchmark sources are repo-local under
`tools/pqc/mlkem` and `tools/pqc/mldsa`. Build the standalone test binaries
there, then copy the selected output into the target rootfs or the `karu`
user's NFS home before running it with `perf_run`:

```sh
make -C tools/pqc/mlkem
make -C tools/pqc/mldsa
```

The ML-KEM example above uses the `xmlkem` binary variants produced by
`tools/pqc/mlkem/test_matrix.sh`. The top-level `make clean` target delegates
to both PQC source trees.

Common overrides:

```sh
ROOTFS_DIR=/srv/nfs/karudeb \
SUITE=trixie \
ROOT_SSH_AUTHORIZED_KEYS=$HOME/.ssh/id_ed25519.pub \
KARUDEB_SSH_AUTHORIZED_KEYS=$HOME/.ssh/id_ed25519.pub \
KARUDEB_SSH_HOST_ED25519_KEY=$PWD/configs/ssh/karudeb_host_ed25519_key \
SERIAL_AUTOLOGIN=0 \
EXTRA_PACKAGES=vim-tiny,tcpdump,libc6-dev,linux-libc-dev,libssl-dev \
KARUDEB_TARGET_CC=clang \
KARUDEB_TARGET_SYSROOT=/srv/nfs/karudeb \
KARUDEB_PERF_USER_ACCESS=2 \
KARUDEB_PERF_EVENT_PARANOID=0 \
./scripts/build-rootfs.sh
```

Set `KARUDEB_PERF_RUN=0` to skip installing `/usr/local/bin/perf_run`, or
`KARUDEB_TARGET_CC=/path/to/clang` to choose the compiler used for target
helpers. `KARUDEB_PERF_RUN_CC` is still accepted as a compatibility alias.
Set `KARUDEB_OPENSSL_ZVK_BENCH=0` to skip installing the OpenSSL RISC-V crypto
benchmark script.
Set `KARUDEB_OPENSSL_ZVK_KAT=0` to skip building the helper used for GCM/GHASH
known-answer tests.
The default root password hash is for the lab password `root`; override
`ROOT_PASSWORD_HASH='*'` to lock the account, or set
`KARUDEB_SHADOW_LAST_CHANGE` if you want normal shadow password aging instead
of the default no-aging value used for no-RTC boards.
The default `karu` password hash is for the lab password `karu`; override
`KARUDEB_USER_PASSWORD_HASH='*'` to lock password authentication for that
account while keeping SSH key login.
The default locale is `C.UTF-8` to keep Perl and other locale-aware tools quiet
without installing generated locale data; override `KARUDEB_LOCALE` if a target
needs a different locale.
The default lab SSH client and host private keys are committed under
`configs/ssh` for repeatable local images. The private client key is not copied
into the image; its public key becomes `authorized_keys`. Override
`KARUDEB_SSH_AUTHORIZED_KEYS` and `KARUDEB_SSH_HOST_ED25519_KEY` for private or
exposed deployments. Set either variable to an empty value to skip installing
that corresponding lab key.

OpenSSL RISC-V vector crypto benchmark suite:

```sh
service karudeb-vnc stop
su - karu
openssl_zvk_bench --quick --seconds 10
```

The script first runs deterministic scalar-vs-vector known-answer checks for
the command-line-exposed primitives plus EVP AES-GCM and the lower-level
`CRYPTO_gcm128_*` GHASH/GCM path, then compares OpenSSL auto-detection against
forced capability strings such as `rv64gc`, `rv64gc_v`, `rv64gc_v_zvkned`, and
`rv64gc_v_zvkb_zvkg_zvkned`. It skips forced extensions that are not present in
`openssl version -a`, and writes raw logs plus `kat.csv` and `summary.csv`
under the printed output directory.

BusyBox serial rescue shell:

```sh
APPEND_EXTRA='init=/usr/local/sbin/karudeb-busybox-init' \
./scripts/run-qemu-9p.sh
```

The rescue init mounts `/proc`, `/sys`, `/dev`, `/run`, and `/tmp` best-effort,
then execs a BusyBox shell on `/dev/console`. For karu64/U-Boot staging, use
the same extra argument:

```sh
APPEND_EXTRA='init=/usr/local/sbin/karudeb-busybox-init' \
./scripts/stage-karu64-tftp.sh
```

Rootfs archives built before this support was added do not contain BusyBox or
the rescue init helper; rebuild and repackage the rootfs before using this boot
argument with an existing NFS or ext4 image.

Builder selection:

```sh
ROOTFS_BUILDER=mmdebstrap ./scripts/build-rootfs.sh
ROOTFS_BUILDER=debootstrap ./scripts/build-rootfs.sh
```

`mmdebstrap` needs QEMU binfmt for foreign-architecture maintainer scripts.
`debootstrap` needs `qemu-riscv64` or `qemu-riscv64-static` in `PATH`.

To recreate an existing rootfs directory:

```sh
FORCE=1 ./scripts/build-rootfs.sh
```

Create a transportable rootfs archive:

```sh
./scripts/package-rootfs.sh
```

The archive records target-side numeric owners. This is the preferred handoff
from a rootless build to a root-owned NFS export directory.

## Kernel requirements

For initramfs-less NFS root, these pieces need to be built in, not modules:

- ns16550/8250 serial console
- target Ethernet driver
- IPv4 autoconfiguration, usually DHCP and static command-line support
- NFS client and root-on-NFS support
- devtmpfs
- ELF and shebang script binary formats
- `CONFIG_BLK_DEV_INITRD` when an initramfs or initrd handoff is used

For QEMU `virt`, the supplied fragment also enables built-in VirtIO networking:

```sh
./scripts/build-qemu-linux.sh
```

The generated kernel image is usually:

```text
build/linux-riscv64/arch/riscv/boot/Image
```

The QEMU wrapper fetches and verifies Linux 7.1.1 under
`build/kernel-source/linux-7.1.1` if the source tree is missing.

By default this builds only `Image`. Set `BUILD_TARGETS='Image modules dtbs'`
if you also need a module tree or board DTBs.

For your real board, merge [configs/linux-riscv64-nfsroot.fragment](configs/linux-riscv64-nfsroot.fragment)
and add your Ethernet driver as built-in.

The same fragment also enables built-in `virtio-9p` support for QEMU:

- `CONFIG_NET_9P=y`
- `CONFIG_NET_9P_VIRTIO=y`
- `CONFIG_9P_FS=y`

## Export the rootfs over NFS

The default QEMU test network is a private TAP network:

- Host: `192.168.76.1/24`
- Guest: `192.168.76.2/24`
- NFS export clients: `192.168.76.0/24`

The karu64 VCU118 netboot convention used by the release Zvk board image is:

- Host TFTP/NFS server: `192.168.42.1/24`
- Board: `192.168.42.10/24`
- NFS export clients: `192.168.42.0/24`
- NFS root path: `/srv/nfs/karudeb`

Export the rootfs:

```sh
./scripts/export-nfs-root.sh
```

This writes `/etc/exports.d/karudeb.exports` and runs `exportfs -ra`. It uses
`no_root_squash` because the guest root filesystem needs normal Unix ownership
semantics during boot.

If the rootfs was built rootless, extract `build/karudeb-riscv64-rootfs.tar.zst`
as root into `/srv/nfs/karudeb` first, then export that directory:

```sh
DEST=/srv/nfs/karudeb ./scripts/install-nfs-root.sh
ROOTFS_DIR=/srv/nfs/karudeb \
CLIENT_CIDR=192.168.42.0/24 \
./scripts/export-nfs-root.sh
```

## Run in QEMU With 9p

Prepare a user-owned 9p rootfs from the packaged rootfs:

```sh
./scripts/install-9p-root.sh
```

Boot it:

```sh
KERNEL=build/linux-riscv64/arch/riscv/boot/Image ./scripts/run-qemu-9p.sh
```

The default kernel command line is equivalent to:

```text
console=ttyS0,115200 earlycon=sbi root=rootfs rootfstype=9p rootflags=trans=virtio,version=9p2000.L,cache=none,msize=512000,access=any rw ip=dhcp
```

The default QEMU 9p device is equivalent to:

```text
-fsdev local,id=rootfs9p,path=build/rootfs-9p,security_model=mapped-xattr,multidevs=remap
-device virtio-9p-device,fsdev=rootfs9p,mount_tag=rootfs
```

`mapped-xattr` lets unprivileged QEMU preserve guest uid/gid/mode metadata in
host extended attributes. `install-9p-root.sh` seeds those xattrs from the
rootfs tar headers so the guest sees target ownership from first boot. Static
device nodes from the archive are skipped during extraction; the guest mounts
`devtmpfs` on `/dev` during boot. If the host filesystem does not support user
xattrs, use `SEED_9P_XATTRS=0` when installing and `NINEP_SECURITY_MODEL=none`
when booting as a fallback.

The host backing tree is also made group-writable by default. That does not
change guest-visible permissions, but it lets QEMU write the tree when QEMU is
run by another user in the same host group. Set `HOST_9P_GROUP_WRITABLE=0` when
installing if you want stricter host-side modes.

`NET_MODE=user` is enabled by default for QEMU 9p so the guest can get DHCP
from QEMU user networking. Use `NET_MODE=none` for a no-network boot.

With QEMU user networking, the default forwarded host ports are:

- `127.0.0.1:2222` to guest SSH port `22`
- `127.0.0.1:5901` to guest VNC display `:1`

Override them with `QEMU_USER_HOSTFWD`, for example:

```sh
QEMU_USER_HOSTFWD='hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:5902-:5901' \
KERNEL=build/linux-riscv64/arch/riscv/boot/Image \
./scripts/run-qemu-9p.sh
```

## JWM Over VNC

When built with `KARUDEB_JWM_VNC=1`, the image creates a locked non-root
`karu` user and installs a manually startable TigerVNC display `:1` service.
Set `KARUDEB_VNC_AUTOSTART=1` only when you want that service enabled at boot.
The session command is:

```sh
jwm >/tmp/jwm.log 2>&1 &
exec xterm -fa Monospace -fs 10 -geometry 100x32 -title karudeb
```

The default VNC service settings are in `/etc/default/karudeb-vnc`:

```sh
ENABLE=1
VNC_USER=karu
VNC_DISPLAY=1
VNC_GEOMETRY=1280x800
VNC_DEPTH=16
VNC_LOCALHOST=no
VNC_SECURITY_TYPES=VncAuth
VNC_PASSWORD=karu
VNC_EXTRA_ARGS=-pixelformat rgb565 -FrameRate 10 -ImprovedHextile=0
```

For QEMU, connect a VNC viewer on the host to:

```text
localhost:5901
```

The default QEMU forward binds to host loopback. The guest VNC service uses
TigerVNC password authentication by default; override `KARUDEB_VNC_PASSWORD`
when building or edit `/etc/default/karudeb-vnc` before exposing this on real
hardware.

This is a minimal VNC session, not a display-manager login. Some desktop logout
or power actions can report D-Bus/session-manager errors in this environment. To
end only the desktop session, stop the service from serial or SSH:

```sh
/etc/init.d/karudeb-vnc stop
```

To stop the whole QEMU guest cleanly, run `poweroff` inside the guest, or use
`make test-vnc-stop` for the scripted detached QEMU smoke test.

## Run JWM/VNC in QEMU With ext4

For the JWM/VNC profile, build an ext4 disk image from the VNC rootfs archive
and boot it as a VirtIO block device. This is the tested path for a detached
QEMU instance that exposes VNC on the host.

The scripted smoke test builds any missing VNC artifacts, launches QEMU in the
background, waits for the forwarded VNC service to answer, and prints the
connection details:

```sh
KERNEL=build/linux-riscv64/arch/riscv/boot/Image ./scripts/test-qemu-vnc.sh
```

Equivalent make targets are:

```sh
make kernel-qemu
make test-vnc
make test-vnc-status
make test-vnc-stop
```

Connect a VNC client to `127.0.0.1:5901` with password `karu` after the script
reports an `RFB` banner. Override `VNC_HOST_PORT` or `SSH_HOST_PORT` if either
default forwarded port is already in use.

Create the ext4 image:

```sh
rm -rf build/rootfs-jwm-vnc-ext4-src
mkdir -p build/rootfs-jwm-vnc-ext4-src

fakeroot -- sh -ec '
  tar --zstd --numeric-owner --no-acls --xattrs \
    --exclude="./dev/*" --exclude="dev/*" \
    -C build/rootfs-jwm-vnc-ext4-src \
    -xf build/karudeb-riscv64-jwm-vnc-rootfs.tar.zst

  install -d -m 0755 -o 0 -g 0 \
    build/rootfs-jwm-vnc-ext4-src/dev \
    build/rootfs-jwm-vnc-ext4-src/dev/pts
  install -d -m 1777 -o 0 -g 0 \
    build/rootfs-jwm-vnc-ext4-src/dev/shm \
    build/rootfs-jwm-vnc-ext4-src/tmp

  cat >build/rootfs-jwm-vnc-ext4-src/etc/fstab <<FSTAB
/dev/vda  /      ext4      defaults,noatime                                                   0  0
proc      /proc  proc      defaults                                                           0  0
sysfs     /sys   sysfs     defaults                                                           0  0
devtmpfs  /dev   devtmpfs  mode=0755                                                          0  0
tmpfs     /run   tmpfs     nosuid,nodev,mode=0755,size=128M                                    0  0
tmpfs     /tmp   tmpfs     nosuid,nodev,size=512M                                              0  0
FSTAB

  rm -f build/rootfs-jwm-vnc.ext4
  truncate -s 3072M build/rootfs-jwm-vnc.ext4
  mkfs.ext4 -q -F -L karudebvnc -d build/rootfs-jwm-vnc-ext4-src build/rootfs-jwm-vnc.ext4
'
```

The root filesystem fsck pass is `0` because the minimal profile does not
include `e2fsprogs` in the guest. If you set it to `1` without adding
`e2fsprogs`, sysvinit drops to maintenance mode before networking and VNC start.

Start a detached QEMU instance with vector enabled and a karu64-compatible
`VLEN=256`:

```sh
rm -f build/qemu-vnc-ext4.log build/qemu-vnc-ext4.err build/qemu-vnc.pid

setsid -f qemu-system-riscv64 \
  -machine virt \
  -cpu rv64,v=true,vlen=256,elen=64 \
  -m 2G \
  -smp 1 \
  -display none \
  -serial file:"$PWD/build/qemu-vnc-ext4.log" \
  -monitor none \
  -bios default \
  -kernel "$PWD/build/linux-riscv64/arch/riscv/boot/Image" \
  -append 'console=ttyS0,115200 root=/dev/vda rw rootwait ip=dhcp earlycon=uart8250,mmio,0x10000000,115200 loglevel=7' \
  -drive file="$PWD/build/rootfs-jwm-vnc.ext4",if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:5901-:5901 \
  -device virtio-net-device,netdev=net0 \
  </dev/null >build/qemu-vnc-ext4.err 2>&1

sleep 2
pgrep -f '^qemu-system-riscv64 .*vlen=256.*root=/dev/vda' | head -1 >build/qemu-vnc.pid
```

Connect the VNC client to `127.0.0.1:5901`. The default VNC password is
`karu`. SSH is also forwarded to `127.0.0.1:2222`.

Useful checks:

```sh
ss -ltnp | grep -E '127[.]0[.]0[.]1:(2222|5901)'
timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5901; head -c 12 <&3'
grep -E 'riscv: base ISA|vector byte|New Xtigervnc' build/qemu-vnc-ext4.log
```

The VNC probe should print an `RFB 003.008` banner. The kernel log should show
`riscv: base ISA extensions acdfhimv` and a vector unaligned-access probe.

Stop the detached instance:

```sh
pid="$(cat build/qemu-vnc.pid)"
kill "$pid"
while ps -p "$pid" >/dev/null 2>&1; do sleep 1; done
e2fsck -fy build/rootfs-jwm-vnc.ext4
```

## Run in QEMU With NFS

Use a kernel with the QEMU VirtIO network driver built in:

```sh
KERNEL=build/linux-riscv64/arch/riscv/boot/Image ./scripts/run-qemu-nfs.sh
```

The default kernel command line is equivalent to:

```text
console=ttyS0,115200 earlycon=sbi root=/dev/nfs rw ip=192.168.76.2:192.168.76.1:192.168.76.1:255.255.255.0:karudeb:eth0:off nfsroot=192.168.76.1:/absolute/path/to/build/rootfs,vers=3,tcp,nolock
```

QEMU user-mode networking cannot see the host loopback interface directly. For
NFS-root testing, TAP is the reliable local-only setup. You can still override
networking with `NET_MODE=user`, but that is mostly useful after the rootfs is
bootable by another path.

Useful QEMU overrides:

```sh
MEMORY=4G \
SMP=2 \
QEMU_CPU='rv64,v=true,vlen=256,elen=64' \
QEMU_EXTRA_ARGS='-d guest_errors' \
KERNEL=/path/to/Image \
./scripts/run-qemu-nfs.sh
```

## Real hardware boot arguments

For the actual diskless target, the bootloader should pass the same shape of
arguments, replacing the QEMU IPs and interface details:

```text
console=ttyS0,115200 root=/dev/nfs rw ip=dhcp nfsroot=<server-ip>:<export-path>,vers=3,tcp,nolock
```

If DHCP is not available:

```text
console=ttyS0,115200 root=/dev/nfs rw ip=<client-ip>:<server-ip>:<gateway-ip>:<netmask>:karudeb:eth0:off nfsroot=<server-ip>:<export-path>,vers=3,tcp,nolock
```

The rootfs does not run a userspace DHCP client by default; the kernel keeps the
address it used to mount NFS.

## karu64 Ethernet/NFS Boot

`../karu64` uses U-Boot to TFTP boot artifacts and then `booti` Linux.
OpenSBI is a board firmware artifact, not a per-ISA-profile image:

```sh
make karu-opensbi
```

The resulting firmware is:

```text
build/karu64/opensbi/fw_jump.bin
build/karu64/opensbi/fw_jump.elf
```

The ROM bitstream targets should source that shared `fw_jump.bin`, then select
only the DTB and netboot command per hardware variant:

```text
Reduced IMAC ROM DTB: build/karu64/karu64-rv64imac-ddr.dtb
RV64GC ROM DTB:       build/karu64/karu64-rv64gc-ddr.dtb
RVA23/Zvk ROM DTB:    build/karu64/karu64-zvk-ddr.dtb
RV64GC netboot:       build/karu64/tftp/rv64gc-ddr/uboot-netboot-one-line.txt
RVA23/Zvk netboot:    build/karu64/tftp/zvk-ddr/uboot-netboot-one-line.txt
```

For the release RVA23/Zvk Debian `riscv64` NFS-root profile, build and stage
the matching rootfs, kernel, and DTB explicitly:

```sh
EXTRA_PACKAGES=vim-tiny,tcpdump,libc6-dev,linux-libc-dev,libssl-dev \
FORCE=1 \
./scripts/build-rootfs.sh
./scripts/package-rootfs.sh

DEST=/srv/nfs/karudeb ./scripts/install-nfs-root.sh
ROOTFS_DIR=/srv/nfs/karudeb \
CLIENT_CIDR=192.168.42.0/24 \
./scripts/export-nfs-root.sh
```

Then build and stage the kernel/DTB pair and generated U-Boot netboot command:

```sh
make karu64-zvk-linux
TFTP_SERVER=192.168.42.1 \
TFTP_ROOT=/srv/tftp \
NFS_SERVER=192.168.42.1 \
GUEST_IP=192.168.42.10 \
GATEWAY_IP=192.168.42.1 \
NFSROOT=/srv/nfs/karudeb \
make karu64-zvk-tftp
```

The generated `build/karu64/tftp/zvk-ddr/uboot-netboot-one-line.txt` is the
default `VCU118_NETBOOT_FILE_VEC` input consumed by `../karu64` when building
the vector ROM board image.

For scalar RV64GC control builds:

```sh
make karu64-rv64gc-linux
make karu64-rv64gc-tftp
```

For the generic RV64GCV/NFS profile without the Zvk DTB extension set:

```sh
./scripts/build-karu64-linux.sh
DTB_VARIANT=ddr ./scripts/build-karu64-dtb.sh
./scripts/stage-karu64-tftp.sh
```

The karu64 kernel wrapper starts from `allnoconfig` and then adds only the
single-board pieces needed for this path: RV64GCV userspace support, 8250 UART,
PLIC, LiteEth, IPv4 autoconfiguration, NFSv3 root, and the RISC-V feature
switches Linux needs to consume detected Supm, Zawrs, Zba/Zbb, and CBO support.
It also enables ELF/script binary formats and initrd support; the allnoconfig
baseline otherwise cannot execute `/sbin/init`, BusyBox, or shebang scripts.

The RV64GC and RV64GCV/Zvk NFS-root board fragments also enable
`CONFIG_PERF_EVENTS`, `CONFIG_RISCV_PMU`, `CONFIG_RISCV_PMU_LEGACY`, and
`CONFIG_RISCV_PMU_SBI`. Together with the rootfs
`kernel.perf_user_access=2` default, this lets benchmark binaries read
`rdcycle` and `rdinstret` directly from userspace on the board. Those direct
CSR reads are not automatically user-only; use perf `:u` events, or
`/usr/local/bin/perf_run --user-count`, when privilege filtering is the
measurement target. On a validated full-vector board run, the live kernel
reported `riscv-pmu-sbi: 16 firmware and 31 hardware counters`, and
`perf_run --user-count` worked for both `root` and `karu`.

The staged `board.dtb` is the feature handoff for OpenSBI/U-Boot/Linux. The DDR
and sim DTBs advertise the default full-vector karu64 profile:

- RV64GCV plus `b`/`zba`/`zbb`/`zbs`
- `zicsr`, `zifencei`, `zicntr`, `zihpm`
- `zca`, `zcb`, `zcmop`
- `zfa`, `zfhmin`, `zicond`, `zimop`, `zawrs`, `zihintntl`, `zihintpause`
- `zicbom`, `zicbop`, `zicboz` with 64-byte CBO block sizes
- Supm through `smnpm` and `ssnpm`
- vector subsets `zve32x`, `zve32f`, `zve64x`, `zve64f`, `zve64d`, `zvfhmin`

The legacy `riscv,isa` string also carries `zvl256b` for tools that consume it.
Linux 7.1.1 does not accept `zvl*` in `riscv,isa-extensions`; it probes the
actual vector length from the vector CSRs. The default DTBs intentionally do not
advertise `zkt`, M-mode pointer masking `smmpm`, opt-in `zvkb`/`zvk*`, full
`zvfh`, `zvbb`, or `zvbc`.

The `zvk-ddr` DTB variant advertises the implemented standard Zvk leaves
(`zvkb`, `zvkg`, `zvkned`, `zvknha`, `zvknhb`, `zvksed`, `zvksh`) plus
`smcntrpmf` and `sscofpmf`. Linux 7.1.1 uses `sscofpmf` for PMU overflow
support and silently ignores the `smcntrpmf` token; OpenSBI consumes the same
structured list and probes the CSRs before programming counter filters for
perf events such as `instructions:u`.
Hardware boot validation confirmed these tokens in
`/proc/device-tree/cpus/cpu@0/riscv,isa-extensions`.
`smstateen`/`ssstateen` are intentionally not advertised for the release
bitstream. The custom Karu Keccak instruction has no official ISA extension
name, so the DTB records it only as `karu,vkeccak` and does not put it in
`riscv,isa`.

This stages `Image`, `board.dtb`, and U-Boot command snippets under
`build/karu64/tftp/<dtb-variant>/` by default. Set `TFTP_ROOT=/srv/tftp` when
you also want to copy the same files into the active host TFTP daemon root.
The staged boot uses
`booti <Image> - <dtb>` and passes `root=/dev/nfs`, so there are no
`linux,initrd-start` / `linux,initrd-end` properties to keep in sync with a flat
image.

Defaults match the karu64 netboot sim/server convention:

```text
serverip=192.168.1.20
ipaddr=192.168.1.10
nfsroot=192.168.1.20:/srv/nfs/karudeb,vers=3,tcp,nolock
```

Override them when staging, for example:

```sh
TFTP_SERVER=192.168.76.1 \
NFS_SERVER=192.168.76.1 \
GUEST_IP=192.168.76.2 \
NFSROOT=/srv/nfs/karudeb \
./scripts/stage-karu64-tftp.sh
```

To stage the sim DTB used by `../karu64`'s vector netboot target:

```sh
DTB_VARIANT=sim OUT_DIR=../karu64/_build/tftp-v ./scripts/stage-karu64-tftp.sh
```

Use `DTB_VARIANT=sim` only for the karu64 `linux_tb`/`uboot-net-sim`
memory map. The default `DTB_VARIANT=ddr` describes the VCU118 DDR map and
assumes the karu64 hardware Ethernet integration is present.

### RV64IMAC soft-float initramfs image

For the reduced `rv64imac` VCU118 bring-up bitstream, this repository also owns
the soft-float kernel and initramfs configuration:

```sh
make karu-rv64imac-check
make karu64-rv64imac-dtb
make karu-rv64imac-image
make karu-rv64imac-tftp
```

The configuration sources are:

- `configs/linux-riscv64-karu64-rv64imac.fragment` for Linux 7.1.1 with
  `CONFIG_FPU` off and the built-in LiteEth driver.
- `configs/busybox-karu64-rv64imac.fragment` for static rv64imac/lp64
  BusyBox plus basic network applets.
- `configs/karu64-rv64imac-{sim,ddr}.dts` for the sim and VCU118 DDR maps.

The generic OpenSBI firmware used by this path is built under
`build/karu64/opensbi/`. The ROM control DTB is available independently as
`build/karu64/karu64-rv64imac-ddr.dtb`; the reduced initramfs image products
stay under `build/karu64-rv64imac-image/`.
The TFTP staging target writes to `build/karu64-rv64imac-tftp/` by default,
not to `../karu64`.
The default DTB is the VCU118 DDR map; use `DTB_VARIANT=sim` for the
`linux_tb` memory map.

The generated kernel is self-contained for early network bring-up:

- `CONFIG_MODULES` is off, so every required driver is built into `vmlinux`.
- `CONFIG_FPU` is off, matching the reduced `rv64imac` core.
- `CONFIG_LITEX_LITEETH` is built in and binds the `litex,liteeth` DT node as
  `eth0`.
- `CONFIG_PHYLIB` and `CONFIG_MDIO_BUS` are off; the DP83867/SGMII setup is
  owned by the karu64 RTL/MDIO initialization, matching the working U-Boot
  LiteEth stack.
- IPv4 autoconfiguration and NFSv3 root support are built in for later
  root-over-network experiments, even though the default boot uses initramfs.

The initramfs is intentionally small and static. It contains `busybox`,
`/bin/sh -> busybox`, `/init`, `/usr/share/udhcpc/default.script`, and a tiny
`/opt/tests/hello-static` syscall smoke test. Keep `/bin/sh` present: if the
kernel reports `Failed to execute /init (error -2)` while `/init` is listed in
the cpio archive, the usual cause is a missing shebang interpreter.

BusyBox is built as static rv64imac/lp64 and includes the networking applets
needed at the shell:

```text
ifconfig ip route netstat ping arping udhcpc nslookup wget
```

The PID 1 script mounts the basic pseudo-filesystems, installs BusyBox applet
symlinks under `/`, brings up `lo`, and if `eth0` exists runs a short DHCP probe:

```sh
udhcpc -i eth0 -q -n -t 2 -T 3
```

`make karu-rv64imac-tftp` stages:

```text
build/karu64-rv64imac-tftp/Image
build/karu64-rv64imac-tftp/initramfs.cpio.gz
build/karu64-rv64imac-tftp/board.dtb
build/karu64-rv64imac-tftp/uboot-initramfs.cmd
build/karu64-rv64imac-tftp/uboot-initramfs-one-line.txt
```

Use the generated U-Boot command file rather than hard-coding the `booti`
initrd size; the size changes whenever the initramfs contents change. For the
DDR hardware DTB the staging addresses are:

```text
Image              0x80200000
initramfs.cpio.gz  0x83000000
board.dtb          0x84000000
```

On real VCU118 bring-up this image has progressed through U-Boot TFTP handoff,
timer/console handoff, LiteEth `eth0` probe, and initramfs unpack on silicon.
