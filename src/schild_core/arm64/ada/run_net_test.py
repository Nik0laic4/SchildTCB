#!/usr/bin/env python3
# Copyright (C) 2026 Alexander Irganov
# SPDX-License-Identifier: GPL-2.0-only
#
# Schild TCB -- ARM64 virtio-net end-to-end validation harness.
#
# Builds the Ada root task + the net-driver child ELF, injects the root task
# into the seL4 elfloader, rebuilds the bootable image, and runs it under QEMU
# with a host-side HTTP server + TCP client.  The guest's protocol stack
# (ARP -> ICMP -> DHCP -> TCP/HTTP -> TCP server -> DNS) runs inside an ELF
# child process with its own VSpace; the harness polls the serial log for the
# success marker and reports pass/fail via the exit code.
#
# Usage:
#   python3 run_net_test.py                         # build + run + check
#   python3 run_net_test.py --skip-build            # run + check (image already built)
#   python3 run_net_test.py --sel4-build-dir PATH   # custom seL4 build directory
#   python3 run_net_test.py --timeout 30
#
# Requirements:
#   - aarch64-linux-gnu-gcc-14 / gnatmake-14 / ld / readelf / objdump
#   - qemu-system-aarch64
#   - the seL4 project (sel4test-manifest) built for qemu-arm-virt (aarch64)
#   - python 'libarchive-c' (only needed when (re)building the elfloader)
#
# The seL4 build directory defaults to /home/null/sel4proj/build; override it
# with --sel4-build-dir.  The success marker is "virtio-net: OK" (printed by the
# Ada root task once the child signals its result notification).

import argparse
import os
import socket
import subprocess
import sys
import threading
import time

SUCCESS_MARKER = b"virtio-net: OK"
FAIL_MARKER = b"virtio-net elf child: failed"
RESP = b"HTTP/1.0 200 OK\r\nContent-Length: 13\r\n\r\nSchildTCB-body"


def http_server():
    """Serve the fixed body the guest fetches over the SLIRP gateway (8080)."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 8080))
    srv.listen(5)
    while True:
        conn, _ = srv.accept()
        try:
            conn.recv(4096)
            conn.sendall(RESP)
        finally:
            conn.close()


def tcp_client():
    """Connect to the guest's TCP server (8081, hostfwd) after the guest has
    reached that stage; this exercises the passive-open path."""
    time.sleep(5)
    for _ in range(15):
        try:
            s = socket.create_connection(("127.0.0.1", 8081), timeout=3)
            time.sleep(0.5)
            s.close()
            return
        except OSError:
            time.sleep(1)


def main():
    p = argparse.ArgumentParser(description="ARM64 virtio-net E2E validation")
    p.add_argument("--skip-build", action="store_true",
                   help="assume the bootable image is already built")
    p.add_argument("--sel4-build-dir", default="/home/null/sel4proj/build",
                   help="seL4 build directory (default: /home/null/sel4proj/build)")
    p.add_argument("--timeout", type=int, default=30,
                   help="QEMU timeout in seconds (default: 30)")
    args = p.parse_args()

    # Keep the harness's own progress lines ordered relative to the subprocess
    # output when the whole stream is piped (Python buffers stdout otherwise).
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass

    ada_dir = os.path.dirname(os.path.abspath(__file__))
    sel4_build = os.path.abspath(args.sel4_build_dir)
    kernel = os.path.join(sel4_build, "images",
                          "sel4test-driver-image-arm-qemu-arm-virt")
    rootserver = os.path.join(sel4_build, "elfloader", "rootserver")

    if not os.path.isdir(sel4_build):
        sys.exit(f"seL4 build dir not found: {sel4_build}")

    if not args.skip_build:
        try:
            import libarchive  # noqa: F401  (needed by the elfloader rebuild)
        except ImportError:
            sys.exit("python 'libarchive-c' is required to rebuild the elfloader "
                     "(pip install libarchive-c), or pass --skip-build")

        print("[harness] ./build_root.sh ...")
        subprocess.run(["./build_root.sh"], cwd=ada_dir, check=True)

        print("[harness] aarch64-linux-gnu-strip -> elfloader/rootserver")
        subprocess.run(["aarch64-linux-gnu-strip", "-o", rootserver,
                        os.path.join(ada_dir, "root_task.elf")], check=True)

        print("[harness] ninja (elfloader relink + image) ...")
        subprocess.run(["ninja"], cwd=sel4_build, check=True)

    if not os.path.exists(kernel):
        sys.exit(f"bootable image not found: {kernel}")

    log = "/tmp/serial.log"
    if os.path.exists(log):
        os.remove(log)

    threading.Thread(target=http_server, daemon=True).start()
    threading.Thread(target=tcp_client, daemon=True).start()
    time.sleep(0.5)

    qemu = subprocess.Popen([
        "qemu-system-aarch64",
        "-machine", "virt,gic-version=2", "-cpu", "cortex-a53", "-m", "size=2G",
        "-no-reboot", "-display", "none", "-monitor", "none",
        "-serial", "file:" + log,
        "-netdev", "user,id=n0,hostfwd=tcp::8081-:8081",
        "-device", "virtio-net-device,netdev=n0,mac=52:54:00:12:34:56",
        "-kernel", kernel,
    ])

    ok = False
    deadline = time.time() + args.timeout
    while time.time() < deadline and qemu.poll() is None:
        if os.path.exists(log):
            data = open(log, "rb").read()
            if SUCCESS_MARKER in data:
                ok = True
                break
            if FAIL_MARKER in data:
                break
        time.sleep(0.25)

    qemu.terminate()
    try:
        qemu.wait(timeout=5)
    except subprocess.TimeoutExpired:
        qemu.kill()

    if os.path.exists(log):
        sys.stdout.buffer.write(open(log, "rb").read())
        sys.stdout.buffer.write(b"\n")

    if ok:
        print("[harness] PASS: virtio-net E2E in an ELF child (own VSpace)")
        return 0
    print("[harness] FAIL: success marker not observed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
