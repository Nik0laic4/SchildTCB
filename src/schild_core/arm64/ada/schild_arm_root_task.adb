-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- Ada/SPARK root task for seL4 on AArch64.
--
-- This is the "Ada root-задача на AArch64" milestone: the same Zero-Footprint-
-- Profile runtime validated by the bare-metal smoke test (hello_world.adb) is
-- used to run the root task under seL4.  Its only I/O is the seL4 debug console
-- (seL4_SysDebugPutChar via Sel4_Syscall.Debug_Put_Char).  There is no OS to
-- return to, so the task halts in a busy loop after printing.
-- =============================================================================

with Sel4_Syscall; use Sel4_Syscall;
with Interfaces;   use Interfaces;

procedure Schild_Arm_Root_Task
  with SPARK_Mode => On
is
   --  Map the virtio-net device into the VSpace and read its MAC (mechanism).
   function Get_Virtio_MAC return Unsigned_64
     with Import, Convention => C, External_Name => "schild_virtio_mac",
          Global => null;

   --  Set up a TX virtqueue, submit a frame, and check it is consumed.
   function Virtio_Net_Test return Unsigned_64
     with Import, Convention => C, External_Name => "schild_virtio_net_test",
          Global => null;

   Counter : Word := 0;
   Mac     : Unsigned_64;
   Hex     : constant String := "0123456789abcdef";

   procedure Put_Byte (B : Unsigned_64) is
   begin
      Debug_Put_Char (Hex (Integer (Shift_Right (B, 4) and 16#F#) + 1));
      Debug_Put_Char (Hex (Integer (B and 16#F#) + 1));
   end Put_Byte;
begin
   Debug_Put_Line ("==== Schild TCB: Ada/SPARK seL4 root task (AArch64) ====");
   Debug_Put_Line ("Root task running under seL4 (DebugPutChar via svc #0).");

   --  A bounded loop so the binary exercises arithmetic and a counter.
   for I in 1 .. 5 loop
      Counter := Counter + Word (I);
   end loop;

   Debug_Put_Str ("sum(1..5) = 0x");
   Debug_Put_Hex (Counter);
   Debug_Put_Line ("");

   Debug_Put_Line ("Hello from Ada (seL4 AArch64 root task)!");

   --  Map the virtio-mmio device region and read the virtio-net MAC.
   Mac := Get_Virtio_MAC;
   if Mac /= 0 then
      Debug_Put_Str ("virtio-net MAC = ");
      for I in 0 .. 5 loop
         Put_Byte (Shift_Right (Mac, 8 * I) and 16#FF#);
         if I < 5 then
            Debug_Put_Char (':');
         end if;
      end loop;
      Debug_Put_Line ("");
   else
      Debug_Put_Line ("virtio-net: mapping failed");
   end if;

   --  Net test: ARP + ICMP echo + DHCP (UDP) + TCP handshake.
   declare
      R : Unsigned_64 := Virtio_Net_Test;
   begin
      if R = 7 then
         Debug_Put_Line ("virtio-net DNS: OK");
      elsif R = 6 then
         Debug_Put_Line ("virtio-net TCP server: OK");
      elsif R = 5 then
         Debug_Put_Line ("virtio-net HTTP: OK");
      elsif R = 4 then
         Debug_Put_Line ("virtio-net DHCP: OK, TCP: none");
      elsif R = 3 then
         Debug_Put_Line ("virtio-net ping: OK, DHCP: none");
      elsif R = 2 then
         Debug_Put_Line ("virtio-net TX+RX (ARP): OK, ICMP: none");
      elsif R = 1 then
         Debug_Put_Line ("virtio-net TX: OK, RX: none");
      else
         Debug_Put_Line ("virtio-net: failed");
      end if;
   end;

   --  Halt: the kernel does not expect the root task to return.
   loop
      null;
   end loop;
end Schild_Arm_Root_Task;
