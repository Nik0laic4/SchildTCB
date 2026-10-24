/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB — seL4 BootInfo structure for x86_64
 * Spec: seL4 Manual §2.2 "BootInfo Frame" (x86_64 ABI).
 * Schild TCB fills this structure, passes to seL4 at kernel entry.
 */
#ifndef SCHILD_SEL4_BOOTINFO_H
#define SCHILD_SEL4_BOOTINFO_H

#include <stdint.h>

typedef uint64_t seL4_Word;

#define SEL4_MAX_UNTYPEDS    64
#define SEL4_BOOTINFO_MAGIC  0x0F1EA9D47A7B3D5CULL

/* Object type codes for Retype */
#define SEL4_OBJECT_TCB           0
#define SEL4_OBJECT_CNODE         1
#define SEL4_OBJECT_VSPACE        2
#define SEL4_OBJECT_FRAME         3
#define SEL4_OBJECT_PAGE_TABLE    4
#define SEL4_OBJECT_PAGE_DIR      5
#define SEL4_OBJECT_PAGE_PDPT     6
#define SEL4_OBJECT_ASID_POOL     7

/* seL4_BootInfo — passed to seL4 kernel at entry. 4 KB page-aligned. */
typedef struct {
    seL4_Word   extraLen;
    seL4_Word   nodeID;
    seL4_Word   numNodes;
    seL4_Word   numIOPTLevels;
    seL4_Word   ipcBuffer;
    seL4_Word   empty;
    seL4_Word   sharedFrames;
    seL4_Word   userImageFrames;
    seL4_Word   userImagePaging;
    seL4_Word   ioSpaceCaps;
    seL4_Word   extraBIPages;
    seL4_Word   initThreadCNodeSizeBits;
    seL4_Word   initThreadDomain;
    struct { seL4_Word start; seL4_Word end; } untyped;
    seL4_Word   numUntypeds;
    seL4_Word   untypedPaddrList[SEL4_MAX_UNTYPEDS];
    seL4_Word   untypedSizeBitsList[SEL4_MAX_UNTYPEDS];
    struct { seL4_Word start; seL4_Word end; } deviceUntyped;
} __attribute__((packed)) seL4_BootInfo;

/* Untyped memory region descriptor */
typedef struct {
    seL4_Word   paddr;
    seL4_Word   size_bits;  /* log2(size), e.g. 20 = 1MB */
} seL4_Untyped_Region;

/* Schild TCB Platform BootInfo context */
typedef struct {
    seL4_Word   sel4_image_paddr;
    seL4_Word   sel4_image_size;
    seL4_Word   kernel_end_paddr;
    seL4_Word   total_ram_mb;
    unsigned int         num_regions;
    seL4_Untyped_Region  regions[SEL4_MAX_UNTYPEDS];
    seL4_BootInfo        boot_info;
} Schild_Platform_BootInfo;

#ifdef __cplusplus
extern "C" {
#endif

int  schild_sel4_init(unsigned long long multiboot_info_addr,
                    unsigned long long kernel_end_addr,
                    Schild_Platform_BootInfo *platform_boot);
void schild_sel4_dump_bootinfo(const Schild_Platform_BootInfo *pb);
void schild_sel4_launch(void) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif
