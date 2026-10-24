-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB -- minimal PL011 UART driver (AArch64 bare-metal).
--
-- Target: qemu-system-aarch64 "-M virt", whose debug console is a PL011 at
-- physical address 0x0900_0000.  This driver is the *mechanism* that lets the
-- bare-metal runtime smoke test print to the emulated serial port.
--
-- CONTRACT BOUNDARY: the specification is SPARK_Mode => On (only Global => null
-- contracts, so it is callable from proved code); the body is SPARK_Mode => Off
-- because memory-mapped device I/O is trusted mechanism, not a proof target.
-- =============================================================================

with Interfaces; use Interfaces;

package UART
  with SPARK_Mode => On
is
   -- Emit one byte on the PL011 data register.  Blocks while the transmit
   -- FIFO is full (device back-pressure).  No global state is touched.
   procedure Put (C : Character)
     with Global => null;

   -- Emit a string (no line terminator).
   procedure Put_Str (S : String)
     with Global => null;

   -- Emit a string followed by CR/LF.
   procedure Put_Line (S : String)
     with Global => null;

   -- Emit a 64-bit value as 16 lowercase hexadecimal digits.
   procedure Put_Hex (V : Unsigned_64)
     with Global => null;
end UART;
