-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- virtio-mmio transport driver (AArch64 bare-metal).
--
-- Target: qemu-system-aarch64 "-M virt", whose first virtio-mmio slot is at
-- 0x0a00_0000 (see the machine DTB).  This driver speaks the virtio-mmio
-- register protocol (virtio spec v1.1, section 4.2) to a virtio-net device and
-- reads its MAC address.
--
-- CONTRACT BOUNDARY: the specification is SPARK_Mode => On (only Global => null
-- contracts, so it is callable from proved code); the body is SPARK_Mode => Off
-- because memory-mapped device I/O is trusted mechanism, not a proof target.
-- =============================================================================

with Interfaces; use Interfaces;

package Virtio_MMIO
  with SPARK_Mode => On
is
   subtype U32 is Unsigned_32;
   subtype U8  is Unsigned_8;

   -- A 48-bit MAC address, byte order as printed (aa:bb:cc:dd:ee:ff).
   type MAC_Address is array (1 .. 6) of U8;

   -- Bring the device into the ACKNOWLEDGE|DRIVER state (reset first).
   procedure Initialize with Global => null;

   -- True if a virtio-net device is present at the first virtio-mmio slot.
   function Is_Virtio_Net return Boolean with Global => null;

   -- Raw register reads (diagnostics).
   function Read_Magic return U32 with Global => null;
   function Read_Device_ID return U32 with Global => null;
   function Read_Device_ID_At (Slot : U32) return U32 with Global => null;

   -- Read the 6-byte MAC address from the virtio-net config space.
   function Read_MAC return MAC_Address with Global => null;
end Virtio_MMIO;
