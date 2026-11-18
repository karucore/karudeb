#!/usr/bin/env python3
"""Exercise the OpenSBI source/version check without network access.

build-karu64-opensbi.sh reuses an existing checkout, so it must not build a
different release than OPENSBI_REF asks for. The fixtures are small Git
repositories whose Makefile writes the checked-out tag into fw_jump.bin, so
each test can see which version was actually built.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/build-karu64-opensbi.sh"
# $(O) is quoted: the work directory has a space in its name on purpose.
MAKEFILE = """all:
\tmkdir -p "$(O)/platform/generic/firmware"
\t(git describe --tags --exact-match 2>/dev/null || echo unversioned) > "$(O)/platform/generic/firmware/fw_jump.bin"
\tcp "$(O)/platform/generic/firmware/fw_jump.bin" "$(O)/platform/generic/firmware/fw_jump.elf"
"""


class OpenSbiSourceTests(unittest.TestCase):
    def setUp(self):
        for tool in ("bash", "git", "make", "gcc"):
            if not shutil.which(tool):
                self.skipTest(f"required tool not found: {tool}")
        temp = tempfile.TemporaryDirectory(prefix="karudeb opensbi ")
        self.addCleanup(temp.cleanup)
        self.work = Path(temp.name)
        self.out = self.work / "out"
        # Upstream fixture with two releases.
        self.upstream = self.work / "upstream"
        self.upstream.mkdir()
        (self.upstream / "Makefile").write_text(MAKEFILE)
        self.git(self.upstream, "init", "-q")
        self.commit(self.upstream, "Makefile", "v1.8.1")
        (self.upstream / "new-in-1.9").write_text("1.9\n")
        self.commit(self.upstream, "new-in-1.9", "v1.9")

    def git(self, source, *args):
        return subprocess.check_output(
            ["git", "-C", str(source), *args], text=True,
            stderr=subprocess.STDOUT, timeout=30,
        ).strip()

    def commit(self, source, name, tag):
        self.git(source, "add", name)
        self.git(source, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-q", "-m", tag)
        self.git(source, "-c", "tag.gpgsign=false", "tag", tag)

    def managed_clone(self, tag, src_dir="src"):
        """A clone where the script keeps its own: SRC_DIR/opensbi."""
        clone = self.work / src_dir / "opensbi"
        clone.parent.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(
            ["git", "clone", "-q", "--depth", "1", "--branch", tag, self.upstream.as_uri(), str(clone)],
            stderr=subprocess.DEVNULL, timeout=30)
        return clone

    def build(self, ref, *, cwd=None, **overrides):
        env = os.environ.copy()
        for name in ("OPENSBI_SRC", "SRC_DIR", "OPENSBI_ALLOW_UNVERSIONED"):
            env.pop(name, None)
        env.update(
            OPENSBI_REF=ref, OPENSBI_LLVM="0", OPENSBI_CROSS_COMPILE="",
            BUILD_DIR=str(self.out), OPENSBI_OUT_DIR=str(self.out),
            OPENSBI_BUILD=str(self.out / "build"), SRC_DIR=str(self.work / "src"),
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", str(SCRIPT), "build"], env=env, cwd=cwd or self.work, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        )

    def built(self):
        return (self.out / "fw_jump.bin").read_text().strip()

    def assert_refused(self, result, text):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stdout)
        self.assertFalse((self.out / "fw_jump.bin").exists(), "nothing may be built from a refused source")

    def test_managed_clone_at_requested_version_is_built(self):
        self.managed_clone("v1.9")
        result = self.build("v1.9")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("Switching OpenSBI source", result.stdout)
        self.assertEqual(self.built(), "v1.9")

    def test_managed_clone_is_upgraded(self):
        clone = self.managed_clone("v1.8.1")
        (self.out / "build").mkdir(parents=True)
        (self.out / "build/stale-object").write_text("from 1.8.1\n")
        result = self.build("v1.9")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Switching OpenSBI source from v1.8.1 to v1.9", result.stdout)
        self.assertEqual(self.git(clone, "describe", "--tags"), "v1.9")
        self.assertEqual(self.built(), "v1.9")
        self.assertFalse((self.out / "build/stale-object").exists(), "old objects must be discarded")

    def test_relative_src_dir_still_upgrades(self):
        # SRC_DIR relative, OPENSBI_SRC unset, relative and absolute.
        for label, overrides in (
            ("unset", {}),
            ("relative", {"OPENSBI_SRC": "src/opensbi"}),
            ("absolute", {"OPENSBI_SRC": str(self.work / "src/opensbi")}),
        ):
            with self.subTest(opensbi_src=label):
                shutil.rmtree(self.work / "src", ignore_errors=True)
                shutil.rmtree(self.out, ignore_errors=True)
                self.managed_clone("v1.8.1")
                result = self.build("v1.9", SRC_DIR="src", **overrides)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn("Switching OpenSBI source from v1.8.1 to v1.9", result.stdout)
                self.assertEqual(self.built(), "v1.9")

    def test_src_dir_through_symlink_still_upgrades(self):
        self.managed_clone("v1.8.1")
        (self.work / "link").symlink_to(self.work / "src", target_is_directory=True)
        result = self.build("v1.9", SRC_DIR=str(self.work / "link"),
                            OPENSBI_SRC=str(self.work / "src/opensbi"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.built(), "v1.9")

    def test_managed_clone_with_local_changes_is_not_switched(self):
        clone = self.managed_clone("v1.8.1")
        (clone / "Makefile").write_text(MAKEFILE + "# local edit\n")
        result = self.build("v1.9")
        self.assert_refused(result, "with local changes")
        self.assertEqual(self.git(clone, "describe", "--tags"), "v1.8.1")

    def test_external_clone_at_other_version_is_refused(self):
        external = self.work / "elsewhere"
        subprocess.check_call(
            ["git", "clone", "-q", "--branch", "v1.9", self.upstream.as_uri(), str(external)],
            stderr=subprocess.DEVNULL, timeout=30)
        result = self.build("v1.8.1", OPENSBI_SRC=str(external))
        self.assert_refused(result, "is at v1.9, not v1.8.1")
        self.assertEqual(self.git(external, "describe", "--tags"), "v1.9", "an external tree is never modified")

    def test_worktree_at_other_version_is_refused(self):
        # A worktree has a .git file, not a directory.
        worktree = self.work / "worktree"
        self.git(self.upstream, "worktree", "add", "-q", str(worktree), "v1.9")
        self.assertTrue((worktree / ".git").is_file())
        result = self.build("v1.8.1", OPENSBI_SRC=str(worktree))
        self.assert_refused(result, "is at v1.9, not v1.8.1")
        result = self.build("v1.9", OPENSBI_SRC=str(worktree))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.built(), "v1.9")

    def test_source_without_git_metadata_needs_opt_in(self):
        plain = self.work / "tarball"
        plain.mkdir()
        (plain / "Makefile").write_text(MAKEFILE)
        result = self.build("v1.9", OPENSBI_SRC=str(plain))
        self.assert_refused(result, "has no Git metadata")
        result = self.build("v1.9", OPENSBI_SRC=str(plain), OPENSBI_ALLOW_UNVERSIONED="1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("unversioned", result.stdout)


if __name__ == "__main__":
    unittest.main()
