# Schild TCB Kernel Makefile
# Build: Multiboot2 boot.S (x86_64) + Ada/SPARK core + C runtime support -> ELF -> ISO
#
# DEPRECATED: the single canonical build entry point is build.sh (fail-hard,
# two-circuit SCHILD_PROFILE). This Makefile is kept only for the legacy
# make qemu / make iso / make clean targets; prefer ./build.sh.
#
# Two-circuit build profile (public = TCB scaffold / private = full):
#   make PROFILE=public     # stub commercial modules
#   make PROFILE=private    # full build (see build.sh for private/ overlay)
PROFILE ?= public

TOOLCHAIN := $(HOME)/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin
TOOLCHAIN_LD := $(HOME)/.local/share/alire/toolchains/gprbuild_22.0.1_24dfc1b5/bin

CC      := $(TOOLCHAIN)/gcc
AS      := $(TOOLCHAIN)/as
LD      := $(TOOLCHAIN_LD)/ld
OBJCOPY := $(TOOLCHAIN)/objcopy
GNAT    := $(TOOLCHAIN)/gnat
GNATMAKE := $(TOOLCHAIN)/gnatmake
GNATBIND := $(TOOLCHAIN)/gnatbind
GNATLINK := $(TOOLCHAIN)/gnatlink

TARGET  := schild_os.elf
ISO     := schild_os.iso
BIN_DIR := build/iso/boot
OBJ_DIR := build/obj

# Flags: bare-metal x86_64, no libc, static
CFLAGS   := -m64 -nostdlib -nostdinc -fno-builtin -fno-stack-protector \
            -mno-red-zone -mno-mmx -mno-sse -mno-sse2 -ffreestanding \
            -Wall -Wextra -O0 -g -I./src

ASFLAGS  := --64

LDFLAGS  := -nostdlib -T linker.ld -z noexecstack -z now

# Kernel Ada sources (order matters: specs before bodies)
ADA_SRC_DIR := src
ADA_DIRS := src src/01_hardware src/02_security src/03_crypto src/04_userland

ADA_FILES := \
	src/schild_uart_driver.adb \
	src/schild_boot_state_machine.adb \
	src/schild_early_init.adb \
	src/schild_boot_runtime.adb \
	src/schild_core.adb \
	src/schild_kernel_entry.adb \
	src/schild_main.adb

# Find all .ads/.adb in subdirectories (for dependencies)
ADA_SPECS := $(shell find src -name '*.ads' 2>/dev/null)
ADA_BODIES := $(shell find src -name '*.adb' 2>/dev/null)

# Assembly source
ASM_SRC := boot.S

# C support sources
C_SRC := src/outb.c

OBJS := $(OBJ_DIR)/boot.o $(OBJ_DIR)/outb.o $(patsubst %.adb, $(OBJ_DIR)/%.o, $(ADA_FILES))

.PHONY: all clean iso qemu compile-ada

all: $(TARGET)

# --- Assemble boot.S ---
$(OBJ_DIR)/boot.o: $(ASM_SRC) linker.ld
	@mkdir -p $(OBJ_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

# --- Compile C sources ---
$(OBJ_DIR)/outb.o: $(C_SRC)
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

# --- Compile Ada manually (no gprbuild for bare-metal) ---
# First generate ALI files for spec-only packages, then bodies
compile-ada: $(ADA_SPECS) $(ADA_BODIES)
	@mkdir -p $(OBJ_DIR)
	@echo "=== Compiling Ada sources ==="
	# Flag -gnatR1: runtime checks off (no runtime library)
	# Flag -nostdlib -nostdinc: no standard includes
	# Flag -gnat2022: Ada 2022 mode
	# Flag -z: compile only, don't bind
	# Flag -g: debug info
	# Flag -O0: no optimization
	# Flag -gnatf: full error messages
	# Flag -gnatVa: all validity checks
	# Flag -gnato: overflow checks
	# Step 1: specifications (spec-only packages)
	$(GNATMAKE) -c -u \
		--RTS=zfp \
		-gnat2022 -gnatwa -gnatwl -gnatf -gnato -gnatVa -g -O0 \
		-nostdlib -nostdinc \
		-I$(OBJ_DIR) \
		-D $(OBJ_DIR) \
		src/schild_uart_driver.ads \
		src/schild_early_init.ads \
		src/schild_boot_state_machine.ads \
		src/schild_boot_runtime.ads \
		src/schild_core.ads \
		src/schild_kernel_entry.ads \
		2>&1
	# Step 2: bodies (body packages)
	$(GNATMAKE) -c -u \
		--RTS=zfp \
		-gnat2022 -gnatwa -gnatwl -gnatf -gnato -gnatVa -g -O0 \
		-nostdlib -nostdinc \
		-I$(OBJ_DIR) \
		-D $(OBJ_DIR) \
		$(ADA_FILES) \
		2>&1

# --- Link ---
$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $(OBJS) $(OBJ_DIR)/b~schild_main.o $(OBJ_DIR)/*.o 2>&1 || \
	$(LD) $(LDFLAGS) -o $@ $(OBJS) 2>&1

# --- ISO image for GRUB2 ---
iso: $(TARGET)
	@mkdir -p $(BIN_DIR)/grub
	cp $(TARGET) $(BIN_DIR)/schild_os.elf
	@echo 'set timeout=0' > $(BIN_DIR)/grub/grub.cfg
	@echo 'set default=0' >> $(BIN_DIR)/grub/grub.cfg
	@echo 'menuentry "Schild TCB x86_64" {' >> $(BIN_DIR)/grub/grub.cfg
	@echo '    multiboot2 /boot/schild_os.elf' >> $(BIN_DIR)/grub/grub.cfg
	@echo '    boot' >> $(BIN_DIR)/grub/grub.cfg
	@echo '}' >> $(BIN_DIR)/grub/grub.cfg
	grub-mkrescue -o $(ISO) build/iso 2>&1 || \
		grub2-mkrescue -o $(ISO) build/iso 2>&1 || echo "grub-mkrescue not found"

# --- Run in QEMU ---
qemu: $(TARGET)
	qemu-system-x86_64 -kernel $(TARGET) -nographic -serial stdio -m 512M -cpu host 2>&1

# --- Clean ---
clean:
	rm -rf build $(OBJ_DIR) *.ali *.o b~*.adb b~*.ads b~*.ali b~*.o $(TARGET) $(ISO)