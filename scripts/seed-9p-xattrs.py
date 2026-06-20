#!/usr/bin/env python3

import errno
import os
import stat
import struct
import sys
import tarfile


XATTR_PREFIX = "user.virtfs."


def die(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def member_mode(member):
    perms = member.mode & 0o7777

    if member.isdir():
        kind = stat.S_IFDIR
    elif member.isfile() or member.islnk():
        kind = stat.S_IFREG
    elif member.issym():
        kind = stat.S_IFLNK
    elif member.ischr():
        kind = stat.S_IFCHR
    elif member.isblk():
        kind = stat.S_IFBLK
    elif member.isfifo():
        kind = stat.S_IFIFO
    else:
        kind = stat.S_IFREG

    return kind | perms


def safe_member_path(root, name):
    while name.startswith("./"):
        name = name[2:]

    if name in ("", "."):
        return root

    if os.path.isabs(name):
        return None

    path = os.path.abspath(os.path.join(root, os.path.normpath(name)))
    if os.path.commonpath((root, path)) != root:
        return None

    return path


def set_u32_xattr(path, name, value):
    os.setxattr(
        path,
        f"{XATTR_PREFIX}{name}",
        struct.pack("<I", value & 0xFFFFFFFF),
        follow_symlinks=False,
    )


def main(argv):
    if len(argv) != 2:
        return die("usage: seed-9p-xattrs.py ROOTFS_DIR < rootfs.tar")

    root = os.path.abspath(argv[1])
    if not os.path.isdir(root):
        return die(f"rootfs directory not found: {root}")

    seeded = 0
    skipped_missing = 0
    skipped_unsafe = 0
    skipped_symlink = 0
    failures = []

    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as archive:
        for member in archive:
            path = safe_member_path(root, member.name)
            if path is None:
                skipped_unsafe += 1
                continue

            if not os.path.lexists(path):
                skipped_missing += 1
                continue

            try:
                set_u32_xattr(path, "uid", member.uid)
                set_u32_xattr(path, "gid", member.gid)
                set_u32_xattr(path, "mode", member_mode(member))
            except OSError as exc:
                if member.issym() and exc.errno in (
                    errno.EPERM,
                    errno.ENOTSUP,
                    errno.EOPNOTSUPP,
                ):
                    skipped_symlink += 1
                    continue
                if exc.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
                    return die(
                        "host filesystem does not support user xattrs; "
                        "use SEED_9P_XATTRS=0 and NINEP_SECURITY_MODEL=none"
                    )
                if len(failures) < 5:
                    failures.append(f"{path}: {exc}")
                continue

            seeded += 1

    if failures:
        print("error: failed to seed some 9p metadata xattrs:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(
        "Seeded QEMU 9p xattrs: "
        f"{seeded} entries"
        f", {skipped_symlink} symlinks skipped"
        f", {skipped_missing} missing entries skipped"
        f", {skipped_unsafe} unsafe entries skipped"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
