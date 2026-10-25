#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- host-side unit test + coverage for the pure protocol logic.
#
# net_test.c is built freestanding for aarch64, but its frame builders/parsers
# (checksum, ARP, IPv4, ICMP, DHCP, UDP, TCP, DNS) are pure buffer-in/out
# functions.  proto_test.c #includes net_test.c, stubs the seL4/driver symbols
# used only by the orchestration path, and exercises the pure functions on the
# host.  This gives fast, QEMU-free statement coverage of the protocol stack.
#
# Usage:
#   ./build_proto_test.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-gcc}"

rm -rf obj_host && mkdir -p obj_host

echo "[proto] compile (host gcc, --coverage) ..."
"$CC" --coverage -O0 -g -I. -o obj_host/proto_test proto_test.c

echo "[proto] run ..."
./obj_host/proto_test

echo "[proto] coverage summary ..."
gcov -o obj_host obj_host/proto_test.gcno 2>/dev/null | grep -E "^File '|^Lines executed" || true

# Leave the annotated sources next to the build for inspection.
echo "[proto] annotated sources: $(pwd)/net_test.c.gcov $(pwd)/proto_test.c.gcov"
