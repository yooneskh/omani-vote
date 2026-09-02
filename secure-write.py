#!/usr/bin/env python3
import os
import stat
import sys


def fail(message):
    sys.stderr.write(message + "\n")
    sys.exit(1)


if len(sys.argv) != 2:
    fail("usage: secure-write.py DEST")

dest = sys.argv[1]
directory = os.path.dirname(dest)
name = os.path.basename(dest)

if not directory or not name or name in (".", ".."):
    fail("invalid destination")

os.makedirs(directory, mode=0o700, exist_ok=True)

try:
    dirfd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
except OSError:
    fail("cannot open destination directory")

tmp_name = None
fd = -1

try:
    if not stat.S_ISDIR(os.fstat(dirfd).st_mode):
        fail("destination parent is not a directory")

    for index in range(64):
        candidate = ".omani-vote-%d-%d" % (os.getpid(), index)
        try:
            fd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=dirfd,
            )
            tmp_name = candidate
            break
        except FileExistsError:
            continue
        except OSError:
            fail("cannot create private temporary file")
    else:
        fail("cannot create private temporary file")

    os.fchmod(fd, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        fail("temporary file is not regular")
    if stat.S_IMODE(info.st_mode) != 0o600:
        fail("temporary file is not 0600")
    if info.st_nlink != 1:
        fail("temporary file is linked")
    if info.st_uid != os.geteuid():
        fail("temporary file owner mismatch")

    payload = sys.stdin.buffer.read()
    written = 0
    while written < len(payload):
        chunk = os.write(fd, payload[written:])
        if chunk <= 0:
            fail("write failed")
        written += chunk

    os.fsync(fd)
    os.close(fd)
    fd = -1
    os.replace(tmp_name, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
    tmp_name = None
finally:
    if fd >= 0:
        try:
            os.close(fd)
        except OSError:
            pass
    if tmp_name:
        try:
            os.unlink(tmp_name, dir_fd=dirfd)
        except OSError:
            pass
    os.close(dirfd)
