-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for Schild_HMAC_SHA256.
--
--   * NIST SHA-256 vectors: "" and "abc" (FIPS 180-4)
--   * RFC 4231 HMAC-SHA256 test cases TC1 .. TC7
--
-- Host-side program (native runtime): run via run_hmac_kat.sh. Exits with a
-- non-zero status if any vector mismatches.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;         use Interfaces;
with Schild_HMAC_SHA256; use Schild_HMAC_SHA256;

procedure Hmac_KAT is

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

   -------------
   -- From_Hex --
   -------------
   function From_Hex (Hex : String) return Byte_Array is
      N : constant Natural := Hex'Length / 2;
      R : Byte_Array (1 .. N);
   begin
      for I in 1 .. N loop
         R (I) := Hex_Val (Hex (Hex'First + 2 * (I - 1))) * 16
                    + Hex_Val (Hex (Hex'First + 2 * (I - 1) + 1));
      end loop;
      return R;
   end From_Hex;

   ----------
   -- Data --
   ----------
   function Data (S : String) return Byte_Array is
      R : Byte_Array (1 .. S'Length);
   begin
      for I in 1 .. S'Length loop
         R (I) := Unsigned_8 (Character'Pos (S (S'First + I - 1)));
      end loop;
      return R;
   end Data;

   ------------
   -- Repeat --
   ------------
   function Repeat (B : Unsigned_8; N : Natural) return Byte_Array is
      R : Byte_Array (1 .. N);
   begin
      for I in 1 .. N loop
         R (I) := B;
      end loop;
      return R;
   end Repeat;

   ------------
   -- Digest --
   ------------
   function Digest (Hex : String) return SHA256_Hash is
      R : SHA256_Hash;
   begin
      for W in 0 .. 3 loop
         declare
            V : Unsigned_64 := 0;
         begin
            for K in 0 .. 15 loop
               V := V * 16
                 + Unsigned_64 (Hex_Val (Hex (Hex'First + W * 16 + K)));
            end loop;
            R (W) := V;
         end;
      end loop;
      return R;
   end Digest;

   ------------
   -- To_Hex --
   ------------
   function To_Hex (H : SHA256_Hash) return String is
      Hex_Chars : constant String := "0123456789abcdef";
      R : String (1 .. 64);
   begin
      for W in 0 .. 3 loop
         for K in 0 .. 15 loop
            R (W * 16 + K + 1) :=
              Hex_Chars
                (Natural (Shift_Right (H (W), (15 - K) * 4) and 16#F#) + 1);
         end loop;
      end loop;
      return R;
   end To_Hex;

   -----------
   -- Check --
   -----------
   procedure Check
     (Name : String; Actual : SHA256_Hash; Expected : SHA256_Hash)
   is
   begin
      if Actual = Expected then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Ada.Text_IO.Put_Line ("  got      " & To_Hex (Actual));
         Ada.Text_IO.Put_Line ("  expected " & To_Hex (Expected));
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Check_SHA
     (Name : String; Msg : Byte_Array; Expected : SHA256_Hash)
   is
   begin
      Check (Name, SHA256 (Msg), Expected);
   end Check_SHA;

   procedure Check_HMAC
     (Name : String; Key : Byte_Array; Msg : Byte_Array; Expected : SHA256_Hash)
   is
   begin
      Check (Name, HMAC_SHA256 (Key, Msg), Expected);
   end Check_HMAC;

begin
   --  NIST SHA-256 vectors.
   Check_SHA
     ("SHA256("""")",
      From_Hex (""),
      Digest ("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
   Check_SHA
     ("SHA256(""abc"")",
      Data ("abc"),
      Digest ("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));

   --  RFC 4231 test cases.
   Check_HMAC
     ("RFC 4231 TC1",
      Repeat (16#0b#, 20),
      Data ("Hi There"),
      Digest ("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"));
   Check_HMAC
     ("RFC 4231 TC2",
      Data ("Jefe"),
      Data ("what do ya want for nothing?"),
      Digest ("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"));
   Check_HMAC
     ("RFC 4231 TC3",
      Repeat (16#aa#, 20),
      Repeat (16#dd#, 50),
      Digest ("773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"));
   Check_HMAC
     ("RFC 4231 TC4",
      From_Hex ("0102030405060708090a0b0c0d0e0f10111213141516171819"),
      Repeat (16#cd#, 50),
      Digest ("82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"));
   Check_HMAC
     ("RFC 4231 TC5",
      Repeat (16#0c#, 20),
      Data ("Test With Truncation"),
      Digest ("a3b6167473100ee06e0c796c2955552bfa6f7c0a6a8aef8b93f860aab0cd20c5"));
   Check_HMAC
     ("RFC 4231 TC6",
      Repeat (16#aa#, 131),
      Data ("Test Using Larger Than Block-Size Key - Hash Key First"),
      Digest ("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"));
   Check_HMAC
     ("RFC 4231 TC7",
      Repeat (16#aa#, 131),
      Data ("This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."),
      Digest ("9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"));

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("HMAC-SHA256 KAT: ALL PASS (9 vectors)");
   else
      Ada.Text_IO.Put_Line
        ("HMAC-SHA256 KAT: " & Natural'Image (Failures) & " FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Hmac_KAT;
