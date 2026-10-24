-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with System;
with Interfaces;

procedure Schild_Kernel_Entry
  (Multiboot_Info : System.Address;
   Fb_Addr        : System.Address;
   Fb_Width       : Interfaces.Unsigned_32;
   Fb_Height      : Interfaces.Unsigned_32;
   Fb_Pitch       : Interfaces.Unsigned_32;
   Fb_Bpp         : Interfaces.Unsigned_32);
pragma Export (C, Schild_Kernel_Entry, "schild_kernel_entry");
