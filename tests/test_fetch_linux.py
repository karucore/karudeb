#!/usr/bin/env python3
"""Exercise stable tarball and mainline RC fetching without network access."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/fetch-linux-source.sh"


class FetchLinuxTests(unittest.TestCase):
    def setUp(self):
        for tool in ("bash", "git", "curl", "tar", "xz", "sha256sum"):
            if not shutil.which(tool):
                self.skipTest(f"required tool not found: {tool}")
        temp = tempfile.TemporaryDirectory(prefix="karudeb kernel ")
        self.addCleanup(temp.cleanup)
        self.work = Path(temp.name)
        self.dest = self.work / "download"

    def git(self, source, *args):
        return subprocess.check_output(
            ["git", "-C", str(source), *args], text=True,
            stderr=subprocess.STDOUT, timeout=30,
        ).strip()

    def tagged_source(self):
        source = self.work / "upstream"
        source.mkdir()
        (source / "Makefile").write_text("# tagged kernel fixture\n")
        self.git(source, "init")
        self.git(source, "add", "Makefile")
        self.git(source, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-m", "test kernel")
        self.git(source, "-c", "tag.gpgsign=false", "tag", "v7.4-rc3")
        return source

    def fetch(self, version, **overrides):
        env = os.environ.copy()
        env.update(
            DEST_DIR=str(self.dest), KERNEL_VERSION=version, KERNEL_SERIES="v7.x",
            KERNEL_BASE_URL=(self.work / "no-network").as_uri(),
            KERNEL_GIT_URL=(self.work / "no-network.git").as_uri(),
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", str(SCRIPT)], env=env, cwd=ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )

    def stable_archive(self, *, bad_checksum=False):
        upstream = self.work / "stable"
        source = upstream / "linux-7.3.4"
        source.mkdir(parents=True)
        (source / "Makefile").write_text("# stable kernel fixture\n")
        archive = upstream / "linux-7.3.4.tar.xz"
        with tarfile.open(archive, "w:xz") as tar:
            tar.add(source, arcname=source.name)
        checksum = "0" * 64 if bad_checksum else hashlib.sha256(archive.read_bytes()).hexdigest()
        (upstream / "sha256sums.asc").write_text(f"{checksum}  {archive.name}\n")
        return upstream

    def test_rc_fetches_exact_tag(self):
        source = self.tagged_source()
        result = self.fetch("7.4-rc3", KERNEL_GIT_URL=source.as_uri())
        self.assertEqual(result.returncode, 0, result.stdout)
        checkout = self.dest / "linux-7.4-rc3"
        self.assertEqual(self.git(checkout, "rev-parse", "HEAD"), self.git(source, "rev-parse", "v7.4-rc3"))
        self.assertEqual(self.git(checkout, "rev-parse", "--is-shallow-repository"), "true")
        self.assertIn("Kernel source commit:", result.stdout)
        self.assertFalse(list(self.dest.glob(".linux-*")))

    def test_existing_source_is_not_refetched(self):
        source = self.tagged_source()
        result = self.fetch("7.4-rc3", KERNEL_GIT_URL=source.as_uri())
        self.assertEqual(result.returncode, 0, result.stdout)
        checkout = self.dest / "linux-7.4-rc3"
        (checkout / "Makefile").write_text("# keep local patches\n")
        result = self.fetch("7.4-rc3")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((checkout / "Makefile").read_text(), "# keep local patches\n")

    def test_missing_rc_tag_leaves_no_partial_source(self):
        source = self.tagged_source()
        result = self.fetch("7.4-rc99", KERNEL_GIT_URL=source.as_uri())
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dest / "linux-7.4-rc99").exists())
        self.assertFalse(list(self.dest.glob(".linux-*")))

    def test_stable_archive_is_verified_and_extracted(self):
        upstream = self.stable_archive()
        result = self.fetch("7.3.4", KERNEL_BASE_URL=upstream.as_uri())
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("linux-7.3.4.tar.xz: OK", result.stdout)
        self.assertEqual((self.dest / "linux-7.3.4/Makefile").read_text(), "# stable kernel fixture\n")

    def test_bad_stable_checksum_prevents_extraction(self):
        upstream = self.stable_archive(bad_checksum=True)
        result = self.fetch("7.3.4", KERNEL_BASE_URL=upstream.as_uri())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED", result.stdout)
        self.assertFalse((self.dest / "linux-7.3.4").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
