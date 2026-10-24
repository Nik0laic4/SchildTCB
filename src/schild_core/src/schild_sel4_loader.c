/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB seL4 Loader — Multiboot2 module tag parser + BootInfo builder.
 * Stage 3: locates seL4 kernel.elf in memory, constructs seL4_BootInfo.
 */

/* Raw types (nostdinc — no stdint.h) */
typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned short     u16;
typedef unsigned char      u8;

/* seL4 BootInfo types */
typedef u64 seL4_Word;
#define SEL4_MAX_UNTYPEDS  64

typedef struct {
    seL4_Word extraLen, nodeID, numNodes, numIOPTLevels;
    seL4_Word ipcBuffer, empty, sharedFrames, userImageFrames, userImagePaging;
    seL4_Word ioSpaceCaps, extraBIPages;
    seL4_Word initThreadCNodeSizeBits, initThreadDomain;
    struct { seL4_Word start; seL4_Word end; } untyped;
    seL4_Word numUntypeds;
    seL4_Word untypedPaddrList[SEL4_MAX_UNTYPEDS];
    seL4_Word untypedSizeBitsList[SEL4_MAX_UNTYPEDS];
    struct { seL4_Word start; seL4_Word end; } deviceUntyped;
} __attribute__((packed)) seL4_BootInfo;

typedef struct { seL4_Word paddr, size_bits; } seL4_Untyped_Region;

typedef struct {
    seL4_Word sel4_image_paddr, sel4_image_size, kernel_end_paddr, total_ram_mb;
    seL4_Word root_task_paddr, root_task_size;  /* Root task module (module3) */
    unsigned int num_regions;
    seL4_Untyped_Region regions[SEL4_MAX_UNTYPEDS];
    seL4_BootInfo boot_info;
} Schild_Platform_BootInfo;

/* === Multiboot2 === */
#define MB2_TAG_END    0
#define MB2_TAG_MODULE 3
#define MB2_TAG_MMAP   6

typedef struct __attribute__((packed)) {
    u64 base_addr, length;
    u32 type;
    u32 reserved;
} mb2_mmap_entry_t;

typedef struct __attribute__((packed)) {
    u32 mod_start, mod_end, string, reserved;
} mb2_module_tag_t;

/* === UART debug === */
static void uart_putc(char c) {
    u8 s;
    do { __asm__ volatile("inb %1, %0" : "=a"(s) : "Nd"(0x3FD)); }
    while (!(s & 0x20));
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(0x3F8));
}
static void uart_puts(const char *s) {
    int i;
    for (i = 0; s[i]; i++) uart_putc(s[i]);
}
static void uart_put_hex64(u64 v) {
    static const char hx[] = "0123456789ABCDEF";
    int i, started = 0;
    uart_putc('0'); uart_putc('x');
    for (i = 60; i >= 0; i -= 4) {
        char c = hx[(v >> i) & 0xF];
        if (c != '0' || started || i == 0) { started = 1; uart_putc(c); }
    }
}
static void uart_put_dec(unsigned long v) {
    char buf[20]; int i = 19;
    if (v == 0) { uart_putc('0'); return; }
    buf[19] = 0;
    while (v > 0) { buf[--i] = '0' + (v % 10); v /= 10; }
    uart_puts(&buf[i]);
}

/* === Helpers === */
static seL4_Word align_up(seL4_Word addr, seL4_Word align) {
    return (addr + align - 1) & ~(align - 1);
}
static seL4_Word size_to_bits(seL4_Word size) {
    seL4_Word bits = 0;
    while (size > 1) { size >>= 1; bits++; }
    return bits;
}

/* ================================================================
 * schild_sel4_init — parse MB2 tags, find seL4 kernel, build BootInfo
 * Returns: 0=OK, 1=no module, 2=invalid
 * ================================================================ */
int schild_sel4_init(unsigned long long multiboot_info_addr,
                   unsigned long long kernel_end_addr,
                   Schild_Platform_BootInfo *pb)
{
    u32 *mbi, total_size;
    u8  *tag_ptr, *tag_end;
    int  found_module = 0;
    int  module_count = 0;
    unsigned int i;

    if (!multiboot_info_addr || !pb) return 2;

    mbi = (u32 *)(unsigned long)multiboot_info_addr;
    total_size = mbi[0];
    tag_ptr = (u8 *)(mbi + 2);
    tag_end = (u8 *)mbi + total_size;

    pb->sel4_image_paddr = 0;
    pb->sel4_image_size  = 0;
    pb->kernel_end_paddr = align_up(kernel_end_addr, 4096);
    pb->total_ram_mb     = 512;
    pb->num_regions      = 0;

    uart_puts("\r\n[SEL4] Scanning Multiboot2 tags...");

    while (tag_ptr < tag_end) {
        u32 tag_type = *(u32 *)tag_ptr;
        u32 tag_size = *(u32 *)(tag_ptr + 4);

        if (tag_type == MB2_TAG_END) break;

        /* --- Module tag (type 3) --- */
        if (tag_type == MB2_TAG_MODULE) {
            mb2_module_tag_t *mod = (mb2_module_tag_t *)(tag_ptr + 8);
            u32 mod_start = mod->mod_start;
            u32 mod_end   = mod->mod_end;
            u32 mod_size  = mod_end - mod_start;

            uart_puts("\r\n[SEL4] Module: start=");
            uart_put_hex64(mod_start);
            uart_puts(" size="); uart_put_dec(mod_size);
            module_count++;

            if (module_count == 1 && mod_size > 32768 && !found_module) {
                pb->sel4_image_paddr = (seL4_Word)mod_start;
                pb->sel4_image_size  = (seL4_Word)mod_size;
                found_module = 1;
                uart_puts(" [seL4 kernel]");
            } else if (module_count == 2 && mod_size > 0) {
                pb->root_task_paddr = (seL4_Word)mod_start;
                pb->root_task_size  = (seL4_Word)mod_size;
                uart_puts(" [root task]");
            }
        }

        /* --- Memory map tag (type 6) --- */
        if (tag_type == MB2_TAG_MMAP) {
            u32 entry_size    = *(u32 *)(tag_ptr + 8);
            u32 entry_version = *(u32 *)(tag_ptr + 12);
            u8  *entries      = tag_ptr + 16;
            u32 num_entries   = (tag_size - 16) / entry_size;
            unsigned int ei;

            for (ei = 0; ei < num_entries; ei++) {
                mb2_mmap_entry_t *ent =
                    (mb2_mmap_entry_t *)(entries + ei * entry_size);

                if (ent->type == 1 &&
                    pb->num_regions < SEL4_MAX_UNTYPEDS) {
                    seL4_Word base = ent->base_addr;
                    seL4_Word len  = ent->length;
                    seL4_Word end  = base + len;

                    if (end > pb->kernel_end_paddr) {
                        seL4_Word fb = base;
                        /* Start at 16MB minimum (avoids seL4 kernel region) */
                        if (fb < 0x1000000ULL)
                            fb = 0x1000000ULL;
                        seL4_Word fs = end - fb;
                        if (fs >= 0x1000) {
                            unsigned int idx = pb->num_regions++;
                            pb->regions[idx].paddr     = fb;
                            pb->regions[idx].size_bits = size_to_bits(fs);
                        }
                    }
                }
            }
        }

        /* 8-byte aligned advance */
        tag_ptr += (tag_size + 7) & ~7U;
    }

    if (!found_module) {
        uart_puts("\r\n[SEL4] ERROR: seL4 kernel module not found!");
        return 1;
    }

    /* ============================================================
     * Build seL4_BootInfo
     * ============================================================ */
    {
        seL4_BootInfo *bi = &pb->boot_info;
        unsigned long clr_i;

        /* Clear */
        for (clr_i = 0; clr_i < sizeof(seL4_BootInfo); clr_i++)
            ((u8 *)bi)[clr_i] = 0;

        bi->extraLen      = 0;
        bi->nodeID        = 0;
        bi->numNodes      = 1;
        bi->numIOPTLevels = 0;
        bi->ipcBuffer     = 0x10000000ULL;  /* 256 MB — safe area */
        bi->empty         = 1;
        bi->sharedFrames  = 0;
        bi->userImageFrames = 1;   /* 1 frame for root task image */
        bi->userImagePaging = 3;   /* PML4 + PDPT + PD for VSpace */
        bi->ioSpaceCaps   = 0;
        bi->extraBIPages  = 0;
        bi->initThreadCNodeSizeBits = 12;
        bi->initThreadDomain = 0;

        /* Fallback: free RAM from SAFE_BASE (16MB) to TOTAL_RAM.
         * Everything below 16MB is Schild TCB + seL4 kernel + BootInfo.
         * Safe margin: seL4 max paddr ~0xA21800 (10.2MB), round up to 16MB. */
        if (pb->num_regions == 0) {
            seL4_Word untyped_start = 0x1000000ULL;  /* 16 MB safe base */
            seL4_Word max_ram = (seL4_Word)pb->total_ram_mb * 1024 * 1024;
            if (untyped_start < max_ram) {
                seL4_Word free_size = max_ram - untyped_start;
                unsigned int idx = pb->num_regions++;
                pb->regions[idx].paddr     = untyped_start;
                pb->regions[idx].size_bits = size_to_bits(free_size);
                uart_puts("\r\n[SEL4] Fallback: free RAM from ");
                uart_put_hex64(untyped_start);
                uart_puts(" size="); uart_put_dec(free_size);
            }
        }

        bi->numUntypeds   = pb->num_regions;
        bi->untyped.start = 0;
        bi->untyped.end   = pb->num_regions;
        {
            unsigned int ui;
            for (ui = 0; ui < pb->num_regions; ui++) {
                bi->untypedPaddrList[ui]    = pb->regions[ui].paddr;
                bi->untypedSizeBitsList[ui] = pb->regions[ui].size_bits;
            }
        }

        bi->deviceUntyped.start = pb->num_regions;
        bi->deviceUntyped.end   = pb->num_regions;

        uart_puts("\r\n[SEL4] BootInfo built: nodes=1, untypeds=");
        uart_put_dec(bi->numUntypeds);
    }

    return 0;
}

/* ================================================================
 * Dump BootInfo to UART
 * ================================================================ */
void schild_sel4_dump_bootinfo(const Schild_Platform_BootInfo *pb)
{
    const seL4_BootInfo *bi = &pb->boot_info;
    unsigned int i;

    uart_puts("\r\n\r\n=== seL4 BootInfo Dump ===");
    uart_puts("\r\n  nodeID:        "); uart_put_dec(bi->nodeID);
    uart_puts("\r\n  numNodes:      "); uart_put_dec(bi->numNodes);
    uart_puts("\r\n  numIOPTLevels: "); uart_put_dec(bi->numIOPTLevels);
    uart_puts("\r\n  ipcBuffer:     "); uart_put_hex64(bi->ipcBuffer);
    uart_puts("\r\n  empty:         "); uart_put_dec(bi->empty);
    uart_puts("\r\n  sharedFrames:  "); uart_put_dec(bi->sharedFrames);
    uart_puts("\r\n  userImgFrames: "); uart_put_dec(bi->userImageFrames);
    uart_puts("\r\n  userImgPaging: "); uart_put_dec(bi->userImagePaging);
    uart_puts("\r\n  ioSpaceCaps:   "); uart_put_dec(bi->ioSpaceCaps);
    uart_puts("\r\n  extraBIPages:  "); uart_put_dec(bi->extraBIPages);
    uart_puts("\r\n  cnodeBits:     "); uart_put_dec(bi->initThreadCNodeSizeBits);
    uart_puts("\r\n  numUntypeds:   "); uart_put_dec(bi->numUntypeds);

    uart_puts("\r\n  --- Untyped Regions ---");
    for (i = 0; i < bi->numUntypeds && i < 8; i++) {
        uart_puts("\r\n    ["); uart_put_dec(i); uart_puts("] paddr=");
        uart_put_hex64(bi->untypedPaddrList[i]);
        uart_puts(" size_bits="); uart_put_dec(bi->untypedSizeBitsList[i]);
    }

    uart_puts("\r\n  --- seL4 Image ---");
    uart_puts("\r\n    paddr: "); uart_put_hex64(pb->sel4_image_paddr);
    uart_puts("\r\n    size:  "); uart_put_dec(pb->sel4_image_size);
    uart_puts(" bytes\r\n");
}

/* ================================================================
 * Launch seL4 — ELF loader + asm gate (Stage 3.3)
 * ================================================================ */

/* === ELF64 types (nostdinc-safe) === */
#define EI_NIDENT    16
#define PT_LOAD      1
#define EM_X86_64    62

typedef u64 Elf64_Addr;
typedef u64 Elf64_Off;

typedef struct {
    u8  e_ident[EI_NIDENT]; u16 e_type, e_machine; u32 e_version;
    Elf64_Addr e_entry; Elf64_Off e_phoff, e_shoff;
    u32 e_flags; u16 e_ehsize, e_phentsize, e_phnum;
    u16 e_shentsize, e_shnum, e_shstrndx;
} __attribute__((packed)) Elf64_Ehdr;

typedef struct {
    u32 p_type, p_flags;
    Elf64_Off  p_offset;
    Elf64_Addr p_vaddr, p_paddr;
    u64 p_filesz, p_memsz, p_align;
} __attribute__((packed)) Elf64_Phdr;

/* Minimal memcpy/memset (bare-metal, no libc) */
static void raw_memcpy(void *d, const void *s, unsigned long n) {
    u8 *dd = (u8 *)d; const u8 *ss = (const u8 *)s;
    unsigned long i;
    for (i = 0; i < n; i++) dd[i] = ss[i];
}
static void raw_memset(void *d, u8 v, unsigned long n) {
    u8 *dd = (u8 *)d; unsigned long i;
    for (i = 0; i < n; i++) dd[i] = v;
}

/*
 * schild_sel4_relocate — copy Schild TCB from 1MB to 2MB, jump there.
 * Frees 0x100000-0x200000 for seL4 kernel. Identity-mapped pages
 * make 2MB immediately accessible. Uses stack pivot + RET.
 */
__attribute__((noinline))
static void schild_sel4_relocate(unsigned long long kernel_end)
{
    unsigned long long src = 0x100000ULL, dst = 0x1000000ULL; /* 16 MB */
    unsigned long long size = kernel_end - src;
    unsigned long long off  = dst - src;
    unsigned long long new_rip;
    uart_puts("\r\n[SEL4] Relocating Schild TCB 0x100000 -> 0x1000000 (16MB)...");
    uart_puts(" copy "); uart_put_dec((unsigned long)size); uart_puts(" bytes");
    raw_memcpy((void*)(unsigned long)dst, (void*)(unsigned long)src,
               (unsigned long)size);
    uart_puts(" done.");
    new_rip = (unsigned long long)__builtin_return_address(0) + off;
    uart_puts("\r\n[SEL4] Jumping to 0x"); uart_put_hex64(new_rip);
    __asm__ volatile(
        "addq %[off], %%rbp\n\t"    /* adjust frame pointer to 16MB area */
        "addq %[off], %%rsp\n\t"
        "pushq %[rip]\n\t"
        "ret\n\t"
        : : [off]"r"(off), [rip]"r"(new_rip) : "memory"
    );
    __asm__ volatile("hlt"); for(;;){__asm__ volatile("hlt");}
}



/* Parse ELF, load PT_LOAD segments to p_paddr, return entry point. */
static Elf64_Addr sel4_elf_load(Schild_Platform_BootInfo *pb,
                                 seL4_Word *out_bootinfo_paddr)
{
    Elf64_Ehdr *ehdr; Elf64_Phdr *phdr;
    int i; Elf64_Addr entry; seL4_Word bip;

    uart_puts("\r\n[SEL4] ELF: pb_ptr=0x"); uart_put_hex64((u64)(unsigned long)pb);
    uart_puts(" paddr=0x"); uart_put_hex64(pb->sel4_image_paddr);
    uart_puts(" size="); uart_put_dec(pb->sel4_image_size);
    uart_puts(" sizeof_ehdr="); uart_put_dec(sizeof(Elf64_Ehdr));

    if (pb->sel4_image_size < sizeof(Elf64_Ehdr)) {
        uart_puts("\r\n[SEL4] ELF: image too small!\r\n"); return 0;
    }
    ehdr = (Elf64_Ehdr *)(unsigned long)pb->sel4_image_paddr;

    if (ehdr->e_ident[0]!=0x7F || ehdr->e_ident[1]!='E' ||
        ehdr->e_ident[2]!='L'  || ehdr->e_ident[3]!='F') {
        uart_puts("\r\n[SEL4] ELF: bad magic!\r\n"); return 0;
    }
    if (ehdr->e_ident[4]!=2) { uart_puts("\r\n[SEL4] ELF: not 64-bit!\r\n"); return 0; }
    if (ehdr->e_machine!=EM_X86_64) { uart_puts("\r\n[SEL4] ELF: not x86_64!\r\n"); return 0; }

    entry = ehdr->e_entry;
    uart_puts("\r\n[SEL4] ELF: entry=0x"); uart_put_hex64(entry);
    uart_puts(" phoff=0x"); uart_put_hex64(ehdr->e_phoff);
    uart_puts(" phnum="); uart_put_dec(ehdr->e_phnum);

    if (!ehdr->e_phoff || !ehdr->e_phnum) {
        uart_puts("\r\n[SEL4] ELF: no program headers!\r\n"); return 0;
    }
    phdr = (Elf64_Phdr *)((u8 *)ehdr + ehdr->e_phoff);

    for (i = 0; i < ehdr->e_phnum; i++) {
        if (phdr[i].p_type == PT_LOAD) {
            u8 *src = (u8 *)ehdr + phdr[i].p_offset;
            u8 *dst = (u8 *)(unsigned long)phdr[i].p_paddr;
            u64 fsz = phdr[i].p_filesz, msz = phdr[i].p_memsz;

            uart_puts("\r\n[SEL4]   LOAD: paddr=0x"); uart_put_hex64(phdr[i].p_paddr);
            uart_puts(" filesz=0x"); uart_put_hex64(fsz);
            uart_puts(" memsz=0x"); uart_put_hex64(msz);

            /* Safety: skip segments that overlap page tables (0x130000-0x150000)
             * or GDT (0x11D000 area). These will be re-set by seL4 itself. */
            if (phdr[i].p_paddr >= 0x120000 && phdr[i].p_paddr < 0x150000) {
                uart_puts(" [SKIP: page tables region]");
                continue;
            }
            if (fsz) {
                uart_puts(" copying...");
                raw_memcpy(dst, src, (unsigned long)fsz);
                uart_puts(" done");
            }
            /* Do NOT zero BSS (memsz - fsz) — seL4 zeroes its own BSS.
             * Our page tables at 0x137000 would be destroyed. */
        }
    }

    bip = pb->kernel_end_paddr + 0x1000;
    *out_bootinfo_paddr = bip;
    raw_memcpy((void*)(unsigned long)bip, &pb->boot_info, sizeof(seL4_BootInfo));
    uart_puts("\r\n[SEL4] BootInfo placed at 0x"); uart_put_hex64(bip);
    return entry;
}

/* ================================================================
 * schild_sel4_launch — ELF load + jump to seL4. Does NOT return.
 * ================================================================ */

/* Static buffer for fake Multiboot2 info (1 KB, plenty for tags) */
static u8 g_fake_mbi[1024] __attribute__((aligned(8)));
static unsigned long g_fake_mbi_size = 0;

/*
 * Build a fake Multiboot2 info structure that seL4 can parse.
 * Contains: memory map tag + root task module tag.
 *
 * seL4's try_boot_sys_mbi2() will find the root task as a module.
 */
static void *build_fake_mbi(Schild_Platform_BootInfo *pb)
{
    u32 *hdr = (u32 *)g_fake_mbi;
    u8  *tag = g_fake_mbi + 8;  /* after 8-byte header */
    u32 *mmap_src = 0;
    u32 mmap_entry_size = 0, mmap_tag_size = 0;
    int i;

    /* Find memory map in original MB2 info (saved from boot) */
    {
        /* Original MB2 info was at multiboot_info_addr, but we don't have it.
         * Instead, build a minimal mmap with one entry: 16MB..512MB */
    }

    /* --- Header --- */
    hdr[0] = 0;  /* total_size — filled at end */
    hdr[1] = 0;  /* reserved */

    /* --- Memory Map tag (type 6) --- */
    /* Minimal: one available RAM region from 16MB to total_ram */
    {
        u32 *t = (u32 *)tag;
        t[0] = 6;   /* type = memory map */
        /* t[1] = size — filled below */
        t[2] = 24;  /* entry_size */
        t[3] = 0;   /* entry_version */
        /* Entry 0: base=0x1000000 (16MB), len=total_ram-16MB, type=1 */
        {
            u64 *ent = (u64 *)(tag + 16);
            u32 *e32 = (u32 *)(tag + 16);
            ent[0] = 0x1000000ULL;  /* base = 16 MB */
            ent[1] = (u64)pb->total_ram_mb * 1024 * 1024 - 0x1000000ULL;
            e32[4] = 1;  /* type = available */
            e32[5] = 0;  /* reserved */
        }
        t[1] = 16 + 24;  /* tag size = header(16) + one entry(24) */
        tag += (t[1] + 7) & ~7U;  /* 8-byte aligned advance */
    }

    /* --- Module tag (type 3) — root task --- */
    {
        u32 *t = (u32 *)tag;
        t[0] = 3;   /* type = module */
        t[1] = 24;  /* size = 8(header) + 16(data) */
        t[2] = (u32)pb->root_task_paddr;       /* mod_start */
        t[3] = (u32)(pb->root_task_paddr + pb->root_task_size); /* mod_end */
        t[4] = 0;   /* string offset (no name) */
        t[5] = 0;   /* reserved */
        tag += 24;  /* 24 = already 8-byte aligned */
    }

    /* --- End tag (type 0) --- */
    {
        u32 *t = (u32 *)tag;
        t[0] = 0;   /* type = end */
        t[1] = 8;   /* size */
        tag += 8;
    }

    /* Fill total_size */
    g_fake_mbi_size = (unsigned long)(tag - g_fake_mbi);
    hdr[0] = (u32)g_fake_mbi_size;

    uart_puts("\r\n[SEL4] Fake MB2 info built: ");
    uart_put_dec(g_fake_mbi_size); uart_puts(" bytes");
    uart_puts(", root_task@0x"); uart_put_hex64(pb->root_task_paddr);

    return g_fake_mbi;
}


void schild_sel4_launch(void)
{
    extern Schild_Platform_BootInfo g_sel4_platform;
    Schild_Platform_BootInfo *pb = &g_sel4_platform;
    Elf64_Addr sel4_entry; seL4_Word bootinfo_paddr;

    /* Step 1: Relocate Schild TCB from 1MB to 16MB, freeing 1MB for seL4 */
    /*
     * Save pb to a global before relocation. After the jump to 16MB,
     * stack-based local variables have wrong frame pointers.
     * Global accessed via RIP-relative addressing survives relocation.
     */
    {
        extern Schild_Platform_BootInfo *g_sel4_pb_saved;
        g_sel4_pb_saved = pb;
    }
    schild_sel4_relocate(pb->kernel_end_paddr);

    /*
     * EXECUTION NOW AT 16MB (0x1000000).
     * Restore pb from global and adjust to 16MB copy.
     */
    {
        extern Schild_Platform_BootInfo *g_sel4_pb_saved;
        unsigned long long reloc_off = 0xF00000ULL;
        pb = g_sel4_pb_saved;
        pb = (Schild_Platform_BootInfo *)((unsigned long long)pb + reloc_off);
        pb->kernel_end_paddr += reloc_off;
    }

    /* Step 2: Build fake Multiboot2 info with root task module */
    void *fake_mbi = build_fake_mbi(pb);

    /* Step 3: Load seL4 ELF into the 1MB area */
    uart_puts("\r\n[SEL4] === Loading seL4 microkernel ===\r\n");
    sel4_entry = sel4_elf_load(pb, &bootinfo_paddr);

    if (!sel4_entry) {
        uart_puts("\r\n[SEL4] *** ELF load FAILED — halting ***\r\n");
        __asm__ volatile("cli; hlt"); for(;;){__asm__ volatile("hlt");}
    }

    uart_puts("\r\n[SEL4] Transferring to seL4...");
    uart_puts("\r\n[SEL4]   Entry=0x"); uart_put_hex64(sel4_entry);
    uart_puts("\r\n[SEL4]   BootInfo=0x"); uart_put_hex64(bootinfo_paddr);
    uart_puts("\r\n[SEL4]   root_task@0x"); uart_put_hex64(pb->root_task_paddr);
    uart_puts("\r\n[SEL4] *** JUMP (no MBI — seL4 needs 32-bit entry, we are 64-bit) ***\r\n\r\n");

    /*
     * NOTE: seL4 entry at 0x100361 is 32-bit Multiboot bootstrap code.
     * We are in 64-bit long mode. Switching back to 32-bit is not
     * implemented. Instead, we jump to the entry without Multiboot magic,
     * and seL4 falls through to try_boot_sys() which works in 64-bit mode.
     * Root task must be started via BootInfo extra fields (future work).
     */
    __asm__ volatile(
        "cli\n\t"
        "movq %[entry], %%rax\n\t"
        "movq %[binfo], %%rsi\n\t"
        "xorq %%rbx, %%rbx\n\t"
        "xorq %%rdi, %%rdi\n\t"
        "jmp *%%rax\n\t"
        : : [entry]"r"(sel4_entry), [binfo]"r"(bootinfo_paddr)
        : "rax","rbx","rdi","rsi","memory"
    );
    __asm__ volatile("hlt"); for(;;){__asm__ volatile("hlt");}
}
