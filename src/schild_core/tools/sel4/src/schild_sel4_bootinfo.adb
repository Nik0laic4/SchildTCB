-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Schild_Sel4_Syscall;

package body Schild_Sel4_BootInfo
  with SPARK_Mode => Off
is
   Hex_Chars : constant String := "0123456789ABCDEF";

   procedure Put_Hex (W : Word) is
   begin
      for I in reverse 0 .. 15 loop
         Schild_Sel4_Syscall.Debug_Put_Char (
            Unsigned_32 (Character'Pos (
               Hex_Chars (Natural (Shift_Right (W, I * 4) and 15) + 1))));
      end loop;
   end Put_Hex;

   procedure Put_Str (S : String) is
   begin
      Schild_Sel4_Syscall.Put_String (S);
   end Put_Str;

   procedure Put_Char (C : Character) is
   begin
      Schild_Sel4_Syscall.Debug_Put_Char (Unsigned_32 (Character'Pos (C)));
   end Put_Char;

   procedure Put_Dec (W : Word) is
      T : Word := W;
      D : array (0 .. 19) of Unsigned_32;
      N : Natural := 0;
   begin
      if T = 0 then Put_Char ('0'); return; end if;
      while T > 0 loop
         D (N) := Unsigned_32 (T mod 10); T := T / 10; N := N + 1;
      end loop;
      for I in reverse 0 .. N - 1 loop
         Put_Char (Character'Val (48 + Natural (D (I))));
      end loop;
   end Put_Dec;
end Schild_Sel4_BootInfo;
