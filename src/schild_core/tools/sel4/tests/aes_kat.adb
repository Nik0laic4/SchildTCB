-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for Schild_Aes_Ni_Core (AES-128, FIPS-197).
--
--   * FIPS-197 Appendix C.1 (AES-128 worked example)
--   * FIPS-197 Appendix B (AES-128 example)
--
-- Host-side program (native runtime): run via run_aes_kat.sh. Exits with a
-- non-zero status if any vector mismatches.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;          use Interfaces;
with Schild_Aes_Ni_Core;  use Schild_Aes_Ni_Core;

procedure Aes_KAT is

   Failures : Natural := 0;

   ------------
   -- Hex_Val --
   ------------
   function Hex_Val (C : Character) return Unsigned_8 is
   begin
      if C in '0' .. '9' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('0'));
      elsif C in 'a' .. 'f' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('a') + 10);
      elsif C in 'A' .. 'F' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('A') + 10);
      else
         return 0;
      end if;
   end Hex_Val;

   --------------
   -- From_Hex --
   --------------
   function From_Hex (S : String) return Aes_Block_Type is
      B : Aes_Block_Type;
   begin
      for I in 0 .. 15 loop
         B (I) := Shift_Left (Hex_Val (S (S'First + 2 * I)), 4)
                    or Hex_Val (S (S'First + 2 * I + 1));
      end loop;
      return B;
   end From_Hex;

   -----------
   -- Check --
   -----------
   procedure Check (Name : String; Plaintext, Key, Ciphertext : String) is
      C : Aes_Block_Type;
   begin
      Encrypt_Aes128_Block (From_Hex (Plaintext), From_Hex (Key), C);
      if C = From_Hex (Ciphertext) then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

begin
   --  FIPS-197 Appendix C.1: AES-128 worked example.
   Check ("FIPS-197 C.1 AES-128",
          "00112233445566778899aabbccddeeff",
          "000102030405060708090a0b0c0d0e0f",
          "69c4e0d86a7b0430d8cdb78070b4c55a");

   --  FIPS-197 Appendix B: AES-128 example.
   Check ("FIPS-197 B AES-128",
          "3243f6a8885a308d313198a2e0370734",
          "2b7e151628aed2a6abf7158809cf4f3c",
          "3925841d02dc09fbdc118597196a0b32");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("AES-128 KAT: ALL PASS (2 vectors)");
   else
      Ada.Text_IO.Put_Line ("AES-128 KAT:" & Natural'Image (Failures) & " FAILURE(S)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Aes_KAT;
