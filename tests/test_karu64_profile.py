#!/usr/bin/env python3
"""Check the opt-in Karu profile DT and boot staging without deployment.

Run directly, or through ``make karu64-rva23s64-check``. Device-tree tools
are required. ``--linux-src /path/to/linux`` additionally runs real Kconfig
merges/olddefconfig, never Image compilation or source patching. All generated
files, including optional TFTP copies, are confined to temporary directories.
"""

import argparse
import copy
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CPU = "/cpus/cpu@0"
BASE_DTS = ROOT / "configs/karu64-zvk-nfsroot-ddr.dts"
PROFILE_DTS = ROOT / "configs/karu64-rva23s64-nfsroot-ddr.dts"
BASE_FRAGMENT = ROOT / "configs/linux-riscv64-karu64-zvk-nfsroot.fragment"
EXTRA_FRAGMENT = ROOT / "configs/linux-riscv64-karu64-rva23s64.fragment"
NEW_LEAVES = {
    "h", "smstateen", "ssstateen", "sstc", "svade", "svinval", "svnapot", "svpbmt",
}
REQUIRED_LEAVES = NEW_LEAVES | {"sscofpmf", "ssnpm", "v", "zvbb", "zvfhmin"}
NETWORK = {
    "TFTP_SERVER": "192.168.42.1", "NFS_SERVER": "192.168.42.1",
    "GUEST_IP": "192.168.42.10", "GATEWAY_IP": "192.168.42.1",
    "NETMASK": "255.255.255.0", "KARUDEB_HOSTNAME": "karudeb",
    "NFSROOT": "/srv/nfs/karudeb", "NFS_OPTS": "vers=3,tcp,nolock",
}
BOOTARGS = (
    "console=ttyS0,115200 earlycon root=/dev/nfs rw "
    "ip=192.168.42.10:192.168.42.1:192.168.42.1:255.255.255.0:karudeb:eth0:off "
    "nfsroot=192.168.42.1:/srv/nfs/karudeb,vers=3,tcp,nolock"
)
LINUX_SRC = None


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_env(**overrides):
    # Do not inherit OUT/DTB/TFTP_ROOT, compiler flags, patch controls or a
    # developer's boot arguments. HOME is only passed through, never changed.
    env = {"PATH": os.environ.get("PATH", os.defpath), "LANG": "C", "LC_ALL": "C"}
    if "HOME" in os.environ:
        env["HOME"] = os.environ["HOME"]
    env.update({key: str(value) for key, value in overrides.items()})
    return env


def run(argv, *, env=None, timeout=60):
    result = subprocess.run(
        [str(arg) for arg in argv], cwd=ROOT, env=env or clean_env(),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {shlex.join(map(str, argv))}\n{result.stdout}")
    return result.stdout


def dt_tree(path):
    """Read every compiled property as bytes; compare actual DTBs, not DTS text."""
    result = {}
    pending = ["/"]
    while pending:
        node = pending.pop()
        props = run(["fdtget", "-p", path, node]).splitlines()
        for prop in props:
            raw = run(["fdtget", "-t", "bx", path, node, prop]).split()
            result[node, prop] = bytes(int(byte, 16) for byte in raw)
        for child in run(["fdtget", "-l", path, node]).splitlines():
            pending.append(node.rstrip("/") + "/" + child)
    return result


def strings(tree, node, prop):
    raw = tree[node, prop]
    require(raw.endswith(b"\0"), f"{node}:{prop} is not a terminated string list")
    return raw[:-1].decode("ascii").split("\0")


def cells(tree, node, prop):
    raw = tree[node, prop]
    require(len(raw) % 4 == 0, f"{node}:{prop} has partial cells")
    return struct.unpack(">" + "I" * (len(raw) // 4), raw)


def isa_tokens(isa):
    parts = isa.split("_")
    require(parts[0].startswith("rv64"), "profile ISA must be RV64")
    tokens = list(parts[0][4:]) + parts[1:]
    require(all(tokens) and len(tokens) == len(set(tokens)), "duplicate or empty ISA extension")
    return set(tokens)


def validate_isa(tree):
    encoded = isa_tokens(strings(tree, CPU, "riscv,isa")[0])
    advertised = strings(tree, CPU, "riscv,isa-extensions")
    require(len(advertised) == len(set(advertised)), "duplicate ISA extension property")
    require(encoded == set(advertised), "ISA string/list disagree")
    require(REQUIRED_LEAVES <= encoded, "missing mandatory profile leaf")
    require(strings(tree, CPU, "riscv,isa-base") == ["rv64i"], "unexpected ISA base")
    return encoded


def validate_board(base, profile):
    # All unlisted bytes must remain identical, including phandles, interrupt
    # routes, peripheral registers, Ethernet slots/MAC and NFS boot arguments.
    allowed = {
        ("/", "model"), (CPU, "riscv,isa"), (CPU, "riscv,isa-extensions"),
        (CPU, "riscv,pmpregions"), (CPU, "riscv,pmpgranularity"),
    }
    require(
        {key: value for key, value in base.items() if key not in allowed}
        == {key: value for key, value in profile.items() if key not in allowed},
        "profile changes board properties outside the allowed ISA/model/PMP set",
    )
    require(cells(profile, "/memory@80000000", "reg") == (0, 0x80000000, 0, 0x80000000), "DDR map changed")
    require(cells(profile, CPU, "clock-frequency") == (75_000_000,), "core clock changed")
    require(cells(profile, "/cpus", "timebase-frequency") == (1_000_000,), "timer frequency changed")
    require(cells(profile, CPU, "reg") == (0,), "hart ID changed")
    require(strings(profile, CPU, "mmu-type") == ["riscv,sv39"], "MMU type changed")
    require(strings(profile, "/chosen", "bootargs") == [BOOTARGS], "lab NFS boot arguments changed")
    require(profile.get((CPU, "karu,vkeccak")) == b"", "Keccak marker missing")
    for operation in ("cbom", "cbop", "cboz"):
        require(cells(profile, CPU, f"riscv,{operation}-block-size") == (64,), "cache-block geometry changed")
    for prop in ("riscv,pmpregions", "riscv,pmpgranularity"):
        require((CPU, prop) not in profile, "profile must not advertise unimplemented PMP entries")


def command_segments(line):
    lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    segments = [[]]
    for token in lexer:
        if token == ";":
            segments.append([])
        else:
            segments[-1].append(token)
    return segments


def validate_netboot(text, retries=3):
    require(len(text.splitlines()) == 1, "ROM boot command must be one line")
    groups = command_segments(text)
    image = " || ".join(["tftpboot 0x80200000 Image"] * retries)
    dtb = " || ".join(["tftpboot 0x84000000 board.dtb"] * retries)
    expected = [
        ["setenv", "serverip", "192.168.42.1"],
        ["setenv", "ipaddr", "192.168.42.10"],
        ["setenv", "karu_fetch_image", image],
        ["setenv", "karu_fetch_dtb", dtb],
        ["setenv", "bootargs", *BOOTARGS.split()],
        ["run", "karu_fetch_image", "&&", "run", "karu_fetch_dtb", "&&",
         "booti", "0x80200000", "-", "0x84000000", "||", "echo", "karu64",
         "netboot:", "TFTP", "failed", "after", str(retries), "attempts", "-",
         "staying", "at", "the", "U-Boot", "prompt"],
    ]
    require(groups == expected, "boot command changes addresses, retry groups, lab network or success gating")


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("bash", "dtc", "fdtget"):
            if not shutil.which(tool):
                raise RuntimeError(f"required host tool not found: {tool}")
        cls.temp = tempfile.TemporaryDirectory(prefix="karudeb-profile-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work = Path(cls.temp.name)
        cls.dtbs = {}
        for variant in ("zvk-ddr", "rva23s64-ddr"):
            output = cls.work / variant
            run(["bash", ROOT / "scripts/build-karu64-dtb.sh"], env=clean_env(
                DTB_VARIANT=variant, OUT_DIR=output,
            ))
            cls.dtbs[variant] = output / f"karu64-{variant}.dtb"
        cls.base = dt_tree(cls.dtbs["zvk-ddr"])
        cls.profile = dt_tree(cls.dtbs["rva23s64-ddr"])
        print(f"profile DTB sha256={digest(cls.dtbs['rva23s64-ddr'])}")

    def test_profile_isa_properties_agree(self):
        validate_isa(self.profile)

    def test_profile_has_only_intended_new_leaves(self):
        base = isa_tokens(strings(self.base, CPU, "riscv,isa")[0])
        self.assertEqual(validate_isa(self.profile), base | NEW_LEAVES)

    def test_legacy_remains_non_h(self):
        self.assertNotIn("h", isa_tokens(strings(self.base, CPU, "riscv,isa")[0]))
        self.assertNotIn("h", strings(self.base, CPU, "riscv,isa-extensions"))

    def test_board_map_clock_network_and_keccak_unchanged(self):
        validate_board(self.base, self.profile)

    def test_profile_pmp_properties_absent(self):
        for prop in ("riscv,pmpregions", "riscv,pmpgranularity"):
            self.assertNotIn((CPU, prop), self.profile)

    def test_short_profile_dtb_alias(self):
        output = self.work / "short-alias"
        run(["bash", ROOT / "scripts/build-karu64-dtb.sh"], env=clean_env(
            DTB_VARIANT="rva23s64", OUT_DIR=output,
        ))
        self.assertEqual((output / "karu64-rva23s64-ddr.dtb").read_bytes(), self.dtbs["rva23s64-ddr"].read_bytes())

    def stage(self, name, variant, *, copy_tftp=False, retries=None):
        work = self.work / name
        work.mkdir()
        kernel = work / "input-Image"
        marker = b"KARU-PROFILE-NONBOOTABLE-TEST-IMAGE\0" + bytes(range(256))
        kernel.write_bytes(marker)
        canonical = "rva23s64-ddr" if variant.startswith("rva23s64") else "zvk-ddr"
        dtb = self.dtbs[canonical]
        out = work / "staged"
        tftp = work / "temporary-tftp" if copy_tftp else None
        env = clean_env(**NETWORK, DTB_VARIANT=variant, KERNEL=kernel, DTB=dtb,
                        OUT_DIR=out, TFTP_ROOT=tftp if tftp else "")
        if retries is not None:
            env["TFTP_RETRIES"] = str(retries)
        run(["bash", ROOT / "scripts/stage-karu64-tftp.sh"], env=env)
        self.assertEqual((out / "Image").read_bytes(), marker)
        self.assertEqual((out / "board.dtb").read_bytes(), dtb.read_bytes())
        self.assertEqual((out / f"karu64-{canonical}.dtb").read_bytes(), dtb.read_bytes())
        line = (out / "uboot-netboot-one-line.txt").read_text()
        validate_netboot(line, retries if retries is not None else 3)
        command = (out / "uboot-netboot.cmd").read_text()
        self.assertIn("if run karu_fetch_image && run karu_fetch_dtb; then\n\tbooti 0x80200000 - 0x84000000\nelse\n", command)
        layout = dict(row.split("=", 1) for row in (out / "layout.env").read_text().splitlines())
        self.assertEqual(layout["DTB_VARIANT"], canonical)
        self.assertEqual(layout["TFTP_ROOT"], str(tftp) if tftp else "")
        self.assertEqual(layout["BOOTARGS"], BOOTARGS)
        self.assertEqual(layout["KERNEL_ADDR"], "0x80200000")
        self.assertEqual(layout["DTB_ADDR"], "0x84000000")
        if tftp:
            self.assertEqual({p.name for p in out.iterdir()}, {p.name for p in tftp.iterdir()})
            for staged in out.iterdir():
                self.assertEqual(staged.read_bytes(), (tftp / staged.name).read_bytes())
        else:
            self.assertFalse((work / "temporary-tftp").exists())
        return line

    def test_profile_staging_without_deployment(self):
        self.stage("profile-stage", "rva23s64-ddr")

    def test_profile_alias_staging_to_temporary_tftp(self):
        self.stage("profile-copy", "rva23s64", copy_tftp=True)

    def test_legacy_staging_still_works(self):
        self.stage("legacy-stage", "zvk-ddr")

    def test_staging_retry_override(self):
        self.stage("retry-stage", "rva23s64-ddr", retries=4)

    def test_mismatched_isa_is_rejected(self):
        bad = copy.deepcopy(self.profile)
        bad[CPU, "riscv,isa-extensions"] = bad[CPU, "riscv,isa-extensions"].replace(b"svpbmt\0", b"")
        with self.assertRaisesRegex(ValueError, "disagree"):
            validate_isa(bad)

    def test_missing_mandatory_leaf_is_rejected(self):
        bad = copy.deepcopy(self.profile)
        bad[CPU, "riscv,isa"] = bad[CPU, "riscv,isa"].replace(b"_svpbmt", b"")
        bad[CPU, "riscv,isa-extensions"] = bad[CPU, "riscv,isa-extensions"].replace(b"svpbmt\0", b"")
        with self.assertRaisesRegex(ValueError, "mandatory"):
            validate_isa(bad)

    def test_board_drift_is_rejected(self):
        bad = copy.deepcopy(self.profile)
        bad[CPU, "clock-frequency"] = struct.pack(">I", 100_000_000)
        with self.assertRaisesRegex(ValueError, "board properties"):
            validate_board(self.base, bad)

    def test_unsafe_boot_gating_is_rejected(self):
        line = self.stage("gating-control", "rva23s64-ddr")
        bad = line.replace("run karu_fetch_image && run karu_fetch_dtb", "run karu_fetch_image; run karu_fetch_dtb")
        with self.assertRaisesRegex(ValueError, "success gating"):
            validate_netboot(bad)


def read_kconfig(path):
    config = {}
    for line in path.read_text().splitlines():
        if line.startswith("CONFIG_"):
            key, value = line.split("=", 1)
            config[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            config[line[2:-11]] = "n"
    return config


class KconfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if LINUX_SRC is None:
            raise unittest.SkipTest("optional Kconfig checks: supply --linux-src")
        source = LINUX_SRC.resolve(strict=True)
        cls.temp = tempfile.TemporaryDirectory(prefix="karudeb-profile-kconfig-")
        cls.addClassCleanup(cls.temp.cleanup)
        work = Path(cls.temp.name)
        no_patches = work / "empty-patches"
        no_patches.mkdir()
        watched = [source / "Makefile", source / "scripts/kconfig/merge_config.sh", BASE_FRAGMENT, EXTRA_FRAGMENT]
        before = {str(path): digest(path) for path in watched}
        cls.configs = {}
        for name in ("base", "profile"):
            output = work / name
            env = clean_env(
                LINUX_SRC=source, OUT_DIR=output, DEFCONFIG="allnoconfig",
                FRAGMENT=BASE_FRAGMENT, EXTRA_FRAGMENT=EXTRA_FRAGMENT if name == "profile" else "",
                BUILD_TARGETS="olddefconfig", FETCH_LINUX_SOURCE="0",
                LINUX_PATCH_DIR=no_patches, INSTALL_MOD_PATH="", LLVM="1", JOBS="2",
            )
            run(["bash", ROOT / "scripts/build-linux.sh"], env=env, timeout=180)
            cls.configs[name] = read_kconfig(output / ".config")
            require(not (output / "arch/riscv/boot/Image").exists(), "Kconfig check unexpectedly built Image")
            print(f"{name} merged Kconfig sha256={digest(output / '.config')}")
        require(before == {str(path): digest(path) for path in watched}, "Kconfig check modified an input")
        print(f"Kconfig source Makefile sha256={before[str(source / 'Makefile')]}")

    def test_profile_enables_kvm_without_changing_legacy(self):
        self.assertEqual(self.configs["profile"]["CONFIG_VIRTUALIZATION"], "y")
        self.assertEqual(self.configs["profile"]["CONFIG_KVM"], "y")
        self.assertEqual(self.configs["base"].get("CONFIG_KVM", "n"), "n")

    def test_profile_preserves_boot_vector_pointer_masking_and_pmu(self):
        for name in (
            "CONFIG_64BIT", "CONFIG_MMU", "CONFIG_FPU", "CONFIG_RISCV_SBI",
            "CONFIG_RISCV_ISA_V", "CONFIG_RISCV_ISA_SUPM", "CONFIG_PERF_EVENTS",
            "CONFIG_RISCV_PMU_SBI", "CONFIG_NFS_FS", "CONFIG_ROOT_NFS",
            "CONFIG_SERIAL_8250_CONSOLE", "CONFIG_SIFIVE_PLIC", "CONFIG_LITEX_LITEETH",
        ):
            with self.subTest(symbol=name):
                self.assertEqual(self.configs["base"].get(name), "y")
                self.assertEqual(self.configs["profile"].get(name), "y")

    def test_extra_fragment_is_only_the_kvm_delta(self):
        self.assertEqual(read_kconfig(EXTRA_FRAGMENT), {"CONFIG_VIRTUALIZATION": "y", "CONFIG_KVM": "y"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linux-src", type=Path, help="also validate real Kconfig merges; no Image build")
    options, unittest_args = parser.parse_known_args()
    LINUX_SRC = options.linux_src
    unittest.main(argv=[__file__, "-v", *unittest_args])
