-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with System.Storage_Elements; use System.Storage_Elements;

package body UART
  with SPARK_Mode => Off  --  MMIO writes are mechanism, not a proof target
is
   -- PL011 register offsets (qemu "-M virt", base 0x0900_0000).
   UART_BASE : constant Integer_Address := 16#0900_0000#;
   DR_Off    : constant Integer_Address := 16#000#;  -- data register
   FR_Off    : constant Integer_Address := 16#018#;  -- flag register

   type Reg is mod 2**32 with Size => 32;

   -- Volatile overlays: every access is a real load/store to the device.
   DR : Reg with Volatile, Address => To_Address (UART_BASE + DR_Off);
   FR : Reg with Volatile, Address => To_Address (UART_BASE + FR_Off);

   TXFF : constant Reg := 2#0010_0000#;  -- transmit FIFO full (FR bit 5)

   procedure Put (C : Character) is
   begin
      -- Wait while the transmit FIFO is full (device back-pressure).
      while (FR and TXFF) /= 0 loop
         null;
      end loop;
      DR := Reg (Character'Pos (C));
   end Put;

   procedure Put_Str (S : String) is
   begin
      for I in S'Range loop
         Put (S (I));
      end loop;
   end Put_Str;

   procedure Put_Line (S : String) is
   begin
      Put_Str (S);
      Put (ASCII.CR);
      Put (ASCII.LF);
   end Put_Line;

   Hex_Digits : constant String := "0123456789abcdef";

   procedure Put_Hex (V : Unsigned_64) is
   begin
      for I in reverse 0 .. 15 loop
         Put (Hex_Digits (Integer (Shift_Right (V, 4 * I) and 16#F#) + 1));
      end loop;
   end Put_Hex;
end UART;
