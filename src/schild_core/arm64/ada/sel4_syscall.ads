-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- minimal seL4 syscall seam for the AArch64 root task.
--
-- CONTRACT BOUNDARY: the specification is SPARK_Mode => On and exposes only the
-- DebugPutChar debug syscall (Global => null) plus pure string/hex helpers, so
-- it is callable from proved root-task code.  The actual syscall (svc #0) is a
-- C shim (sel4_stubs.c) -- trusted mechanism, not a proof target.
-- =============================================================================

with Interfaces; use Interfaces;

package Sel4_Syscall
  with SPARK_Mode => On
is
   subtype Word is Unsigned_64;

   -- seL4 debug console: seL4_SysDebugPutChar (syscall number -9).  The single
   -- character is passed in x0 and the syscall id in x7 by the C shim.
   procedure Debug_Put_Char (C : Character)
     with Import, Convention => C, External_Name => "schild_sel4_debug_putchar",
          Global => null;

   -- Emit a string (no terminator), a line, and a 64-bit value as 16 hex digits.
   procedure Debug_Put_Str  (S : String) with Global => null;
   procedure Debug_Put_Line (S : String) with Global => null;
   procedure Debug_Put_Hex  (V : Word)   with Global => null;
end Sel4_Syscall;
