#!/usr/bin/env bash
# C4 libFuzzer — build + run the coverage-guided harnesses.
#   ./fuzz_libfuzzer.sh all       (default: build + run 60s each)
#   ./fuzz_libfuzzer.sh build
#   ./fuzz_libfuzzer.sh run
set -euo pipefail
cd "$(dirname "$0")"

TIME="${LIBFUZZER_TIME:-60}"

build() {
    clang -fsanitize=fuzzer,address,undefined -O1 -g -o shared_frame_libfuzzer shared_frame_libfuzzer.c
    clang -fsanitize=fuzzer,address,undefined -O1 -g -o seam_libfuzzer seam_libfuzzer.c
    clang -fsanitize=fuzzer,address,undefined -O1 -g -I../src -o fs_dispatch_libfuzzer fs_dispatch_libfuzzer.c
    clang -fsanitize=fuzzer,address,undefined -O1 -g -o mls_dispatch_libfuzzer mls_dispatch_libfuzzer.c
}

run() {
    for t in shared_frame_libfuzzer seam_libfuzzer fs_dispatch_libfuzzer mls_dispatch_libfuzzer; do
        echo "=== $t (${TIME}s) ==="
        ./"$t" -max_total_time="$TIME" || { echo "$t: CRASH" >&2; exit 1; }
    done
}

case "${1:-all}" in
    build) build ;;
    run)   run ;;
    all)   build && run ;;
    *) echo "usage: $0 {all|build|run}" >&2; exit 2 ;;
esac
