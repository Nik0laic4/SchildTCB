-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Conversion;
with System.Storage_Elements; use System.Storage_Elements;

package body Virtio_MMIO
  with SPARK_Mode => Off  -- MMIO is mechanism, not a proof target
is
   -- qemu "-M virt": the virtio-mmio transport spans 32 slots at 0x0a00_0000,
   -- 0x200 bytes apart.  QEMU attaches devices to the slots in REVERSE order:
   -- the first "-device" lands on bus.31 at 0x0a00_3e00, the next on bus.30,
   -- and so on.  A single virtio-net device therefore lives at 0x0a00_3e00.
   -- (A full driver should scan all 32 slots for the wanted DeviceID.)
   Base : constant U32 := 16#0A00_3E00#;

   -- Virtio-mmio register offsets (virtio spec v1.1, section 4.2.2).
   Off_Magic     : constant U32 := 16#000#;
   Off_Device_ID : constant U32 := 16#008#;
   Off_Status    : constant U32 := 16#040#;
   Off_Config    : constant U32 := 16#100#;

   -- Volatile overlays at the fixed device addresses: every access is a real
   -- load/store to the device.
   Magic    : U32 with Volatile, Address => To_Address (Integer_Address (Base + Off_Magic));
   DeviceID : U32 with Volatile, Address => To_Address (Integer_Address (Base + Off_Device_ID));
   Status   : U32 with Volatile, Address => To_Address (Integer_Address (Base + Off_Status));
   -- virtio-net config space: mac[0..3] at 0x100, mac[4..5] + status at 0x104.
   Mac0     : U32 with Volatile, Address => To_Address (Integer_Address (Base + Off_Config));
   Mac1     : U32 with Volatile, Address => To_Address (Integer_Address (Base + Off_Config + 4));

   Magic_Value       : constant U32 := 16#7472_6976#;  -- "virt"
   Device_ID_Network : constant U32 := 1;

   Status_Acknowledge : constant U32 := 2#0001#;
   Status_Driver      : constant U32 := 2#0010#;

   procedure Initialize is
   begin
      Status := 0;                                    -- reset
      Status := Status_Acknowledge;                   -- ACKNOWLEDGE
      Status := Status_Acknowledge or Status_Driver;  -- ACKNOWLEDGE | DRIVER
   end Initialize;

   function Is_Virtio_Net return Boolean is
   begin
      return Magic = Magic_Value and then DeviceID = Device_ID_Network;
   end Is_Virtio_Net;

   function Read_Magic return U32 is (Magic);
   function Read_Device_ID return U32 is (DeviceID);

   type U32_Ptr is access all U32;
   function To_U32_Ptr is new Ada.Unchecked_Conversion (System.Address, U32_Ptr);

   function Read_Device_ID_At (Slot : U32) return U32 is
      -- virtio-mmio slots are 0x200 bytes apart (qemu "-M virt").
      Addr : constant System.Address :=
         To_Address (Integer_Address (16#0A00_0000# + Slot * 16#200# + Off_Device_ID));
      P : constant U32_Ptr := To_U32_Ptr (Addr);
   begin
      return P.all;
   end Read_Device_ID_At;

   function Read_MAC return MAC_Address is
      M0 : constant U32 := Mac0;
      M1 : constant U32 := Mac1;
   begin
      -- The config-space MAC is a byte array; on little-endian AArch64 the
      -- first byte (mac[0]) sits in the least-significant byte of the word.
      return [U8 (M0 and 16#FF#),
              U8 (Shift_Right (M0,  8) and 16#FF#),
              U8 (Shift_Right (M0, 16) and 16#FF#),
              U8 (Shift_Right (M0, 24) and 16#FF#),
              U8 (M1 and 16#FF#),
              U8 (Shift_Right (M1,  8) and 16#FF#)];
   end Read_MAC;
end Virtio_MMIO;
