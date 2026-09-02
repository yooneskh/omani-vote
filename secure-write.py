#!/usr/bin/env python3
import os
import stat
import sys


STATE_PARTS = (".local", "state", "omarchy")
STATE_NAME = "yooneskh.omani-vote.json"
MAX_BYTES = 8192
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC


def fail(message):
    sys.stderr.write(message + "\n")
    sys.exit(1)


def valid_home(path):
    if not path or not path.startswith("/") or "\0" in path:
        return False
    if any(ord(ch) < 32 for ch in path):
        return False
    parts = path.split("/")
    if parts[0] != "":
        return False
    return all(part not in ("", ".", "..") for part in parts[1:])


def verify_dir(fd):
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        fail("not a directory")
    if info.st_uid != os.geteuid():
        fail("directory owner mismatch")
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        fail("directory is group or world writable")


def enter(dirfd, name, create):
    flags = DIR_FLAGS | os.O_NOFOLLOW
    try:
        fd = os.open(name, flags, dir_fd=dirfd)
    except FileNotFoundError:
        if not create:
            os.close(dirfd)
            raise
        try:
            os.mkdir(name, 0o700, dir_fd=dirfd)
        except FileExistsError:
            pass
        except OSError:
            os.close(dirfd)
            fail("cannot create " + name)
        try:
            fd = os.open(name, flags, dir_fd=dirfd)
        except OSError:
            os.close(dirfd)
            fail("cannot open " + name)
    except OSError:
        os.close(dirfd)
        fail("cannot open " + name)

    try:
        verify_dir(fd)
    except Exception:
        os.close(fd)
        os.close(dirfd)
        raise
    os.close(dirfd)
    return fd


def trusted_omarchy_dir(home, create):
    try:
        fd = os.open(home, DIR_FLAGS)
    except OSError:
        fail("cannot open home")
    try:
        verify_dir(fd)
    except Exception:
        os.close(fd)
        raise
    for part in STATE_PARTS:
        fd = enter(fd, part, create)
    return fd


def read_capped(stream, limit):
    payload = stream.read(limit + 1)
    if len(payload) > limit:
        fail("payload too large")
    return payload


def do_write(home):
    dirfd = trusted_omarchy_dir(home, create=True)
    payload = read_capped(sys.stdin.buffer, MAX_BYTES)
    tmp_name = None
    fd = -1
    try:
        for index in range(64):
            candidate = ".omani-vote-%d-%d" % (os.getpid(), index)
            try:
                fd = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
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

        written = 0
        while written < len(payload):
            chunk = os.write(fd, payload[written:])
            if chunk <= 0:
                fail("write failed")
            written += chunk

        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(tmp_name, STATE_NAME, src_dir_fd=dirfd, dst_dir_fd=dirfd)
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


def do_read(home):
    try:
        dirfd = trusted_omarchy_dir(home, create=False)
    except FileNotFoundError:
        sys.exit(2)

    try:
        fd = os.open(STATE_NAME, FILE_FLAGS, dir_fd=dirfd)
    except FileNotFoundError:
        os.close(dirfd)
        sys.exit(2)
    except OSError:
        os.close(dirfd)
        fail("cannot open state file")

    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            fail("state is not a regular file")
        if info.st_uid != os.geteuid():
            fail("state owner mismatch")
        if info.st_nlink != 1:
            fail("state file is linked")
        if info.st_size > MAX_BYTES:
            fail("state file too large")
        data = os.read(fd, info.st_size + 1)
        if len(data) != info.st_size:
            fail("state file size mismatch")
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    finally:
        os.close(fd)
        os.close(dirfd)


if len(sys.argv) != 3 or sys.argv[1] not in ("read", "write"):
    fail("usage: secure-write.py read|write HOME")

home = sys.argv[2]
if not valid_home(home):
    fail("invalid home")

if sys.argv[1] == "write":
    do_write(home)
else:
    do_read(home)
