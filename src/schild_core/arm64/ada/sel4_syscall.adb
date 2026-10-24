-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Sel4_Syscall
  with SPARK_Mode => On
is
   procedure Debug_Put_Str (S : String) is
   begin
      for I in S'Range loop
         Debug_Put_Char (S (I));
      end loop;
   end Debug_Put_Str;

   procedure Debug_Put_Line (S : String) is
   begin
      Debug_Put_Str (S);
      Debug_Put_Char (ASCII.CR);
      Debug_Put_Char (ASCII.LF);
   end Debug_Put_Line;

   Hex_Digits : constant String := "0123456789abcdef";

   procedure Debug_Put_Hex (V : Word) is
   begin
      for I in reverse 0 .. 15 loop
         Debug_Put_Char (Hex_Digits (Integer (Shift_Right (V, 4 * I) and 16#F#) + 1));
      end loop;
   end Debug_Put_Hex;
end Sel4_Syscall;
