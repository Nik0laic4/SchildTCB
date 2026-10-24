# seL4 Microkernel — Integration Point

## Status: Stage 3 (BootInfo ready, awaiting kernel binary)

Place the compiled `kernel.elf` from seL4 (x86_64) here.
Build command:
  cd seL4 && mkdir build && cd build
  ../init-build.sh -DPLATFORM=pc99 -DSIMULATION=TRUE
  ninja
  cp images/kernel-x86_64-pc99 kernel.elf

Then enable seL4 in Schild TCB:
  ENABLE_SEL4=1 ./build.sh
