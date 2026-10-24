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
   Counter : Word := 0;
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

   --  Halt: the kernel does not expect the root task to return.
   loop
      null;
   end loop;
end Schild_Arm_Root_Task;
