# Schild TCB — reproducible build & verification container.
#
# Mirrors the exact steps of .github/workflows/ci.yml, so the image is validated
# against the same toolchain versions CI uses (Alire alr 2.1.1, gnat_native
# 14.2.1, gprbuild 22.0.1, gnatprove). NOT yet certified for DO-330/DO-333 —
# this is a reproducibility aid, not a qualification artifact (see
# docs/technical/TOOL_QUALIFICATION.md).
#
# Usage (from the repo root):
#   docker build -t schild-tcb .
#
#   # build + root-task verification (fast)
#   docker run --rm -v "$PWD":/repo schild-tcb
#
#   # full 185-module SPARK Level-4 proof (tens of minutes)
#   docker run --rm -v "$PWD":/repo schild-tcb prove-full

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    ALR_VERSION=2.1.1

# System dependencies: grub-mkrescue (xorriso/mtools), QEMU for runtime tests,
# python3 for the SchildFS image builder, C toolchain for the bare-metal shims.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip git make binutils gcc \
        grub-pc-bin grub-common xorriso mtools \
        qemu-system-x86 python3 \
    && rm -rf /var/lib/apt/lists/*

# Alire (alr) — pinned to the CI version.
RUN mkdir -p "$HOME/.local/bin" \
    && curl -fsSL -o /tmp/alr.zip \
         "https://github.com/alire-project/alire/releases/download/v${ALR_VERSION}/alr-${ALR_VERSION}-bin-x86_64-linux.zip" \
    && unzip -o /tmp/alr.zip -d /tmp/alr-dist \
    && cp "$(find /tmp/alr-dist -name alr -type f | head -1)" "$HOME/.local/bin/alr" \
    && chmod +x "$HOME/.local/bin/alr" \
    && rm -rf /tmp/alr.zip /tmp/alr-dist \
    && "$HOME/.local/bin/alr" --version

ENV PATH="$HOME/.local/bin:$HOME/.alire/bin:$PATH"

# Ada/SPARK toolchain (same versions as CI).
RUN alr -n toolchain --select gnat_native=14.2.1 \
    && alr -n toolchain --select gprbuild=22.0.1 \
    && alr -n install gnatprove

WORKDIR /repo

# Entrypoint: build + verify (default) or the full proof sweep.
COPY <<'EOF' /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail
cd /repo/src/schild_core
case "${1:-}" in
  prove-full)
    bash scripts/prove_kernel.sh ;;
  verify)
    ./build.sh && bash scripts/verify.sh && bash scripts/verify_private.sh ;;
  *)
    ./build.sh && bash scripts/verify.sh ;;
esac
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["verify"]
