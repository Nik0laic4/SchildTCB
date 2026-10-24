-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- bare-metal runtime smoke test for AArch64.
--
-- This program proves the Zero-Footprint-Profile runtime (bare_runtime) and the
-- cross-GNAT toolchain work on AArch64 without an operating system: it is
-- compiled against --RTS=bare_runtime, linked at a fixed address, and booted by
-- qemu-system-aarch64 "-M virt".  Its only I/O is the PL011 UART (see UART).
--
-- This is the "bare-metal runtime under ARM64" milestone: a green run here is
-- the precondition for the Ada seL4 root task (schild_arm_root_task.adb).
-- =============================================================================

with UART;       use UART;
with Interfaces; use Interfaces;

procedure Hello_World
  with SPARK_Mode => On
is
   Counter : Unsigned_64 := 0;
begin
   Put_Line ("==== Schild TCB: Ada/SPARK bare-metal runtime (AArch64) ====");
   Put_Line ("Zero-Footprint-Profile runtime + cross-GNAT 14, no OS.");

   --  A bounded loop so the binary exercises arithmetic and a counter.
   for I in 1 .. 5 loop
      Counter := Counter + Unsigned_64 (I);
   end loop;

   Put_Str ("sum(1..5) = 0x");
   Put_Hex (Counter);
   Put_Line ("");

   Put_Line ("Hello from Ada (AArch64)!");
   Put_Line ("Runtime OK.");

   --  Halt: there is no operating system to return to.
   loop
      null;
   end loop;
end Hello_World;
