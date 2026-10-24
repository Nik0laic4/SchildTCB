-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- virtio-net device probe (AArch64 bare-metal).
--
-- Boots in qemu-system-aarch64 "-M virt" with a virtio-net device, brings the
-- first virtio-mmio slot into the DRIVER state, verifies it is a virtio-net
-- device, and prints its MAC address over the PL011 UART.  This validates the
-- virtio-mmio driver (Virtio_MMIO) before it is ported to the seL4 root task,
-- where the MMIO region must additionally be mapped into the VSpace.
-- =============================================================================

with UART;        use UART;
with Virtio_MMIO; use Virtio_MMIO;
with Interfaces;  use Interfaces;

procedure Virtio_Probe
  with SPARK_Mode => On
is
   Hex : constant String := "0123456789abcdef";

   procedure Put_Byte_Hex (B : U8) is
   begin
      Put (Hex (Integer (Shift_Right (B, 4) and 16#F#) + 1));
      Put (Hex (Integer (B and 16#F#) + 1));
   end Put_Byte_Hex;

   Mac : MAC_Address;
begin
   Put_Line ("==== Schild TCB: virtio-net probe (AArch64 bare-metal) ====");

   Initialize;

   if Is_Virtio_Net then
      Mac := Read_MAC;
      Put_Str ("virtio-net found, MAC = ");
      for I in 1 .. 6 loop
         Put_Byte_Hex (Mac (I));
         if I < 6 then
            Put (':');
         end if;
      end loop;
      Put_Line ("");
   else
      Put_Line ("virtio-net device NOT found (add -device virtio-net-device)");
   end if;

   --  Halt: there is no operating system to return to.
   loop
      null;
   end loop;
end Virtio_Probe;
