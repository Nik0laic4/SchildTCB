/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB seL4 Boot Runtime — compatibility wrapper (nostdinc-safe).
 * Delegates to schild_sel4_loader.c for Multiboot2 parsing + BootInfo build.
 */
typedef unsigned long long uint64_t;

/* Forward declarations matching loader.c types */
typedef uint64_t seL4_Word;
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
    seL4_Word root_task_paddr, root_task_size;
    unsigned int num_regions;
    seL4_Untyped_Region regions[SEL4_MAX_UNTYPEDS];
    seL4_BootInfo boot_info;
} Schild_Platform_BootInfo;

/* External functions from loader.c */
extern int  schild_sel4_init(unsigned long long, unsigned long long, Schild_Platform_BootInfo *);
extern void schild_sel4_dump_bootinfo(const Schild_Platform_BootInfo *);
extern void schild_sel4_launch(void);

/* Global platform boot context */
Schild_Platform_BootInfo g_sel4_platform;

/* Saved pb pointer for relocation (survives 1MB→16MB jump) */
Schild_Platform_BootInfo *g_sel4_pb_saved;

/* Called from Ada — returns 0=seL4 ready, 1=no module, 2=MB2 error */
int schild_sel4_launch_init(unsigned long long multiboot_info_addr,
                          unsigned long long kernel_end_addr)
{
    int rc = schild_sel4_init(multiboot_info_addr, kernel_end_addr,
                            &g_sel4_platform);
    if (rc == 0) {
        schild_sel4_dump_bootinfo(&g_sel4_platform);
        schild_sel4_launch();
    }
    return rc;
}

/* Legacy compat */
void schild_sel4_boot_init(unsigned long long mi,
                         unsigned long long magic,
                         unsigned long long *umem,
                         unsigned long long *usize)
{
    (void)magic; (void)umem; (void)usize;
    schild_sel4_launch_init(mi, 0x200000);
}
