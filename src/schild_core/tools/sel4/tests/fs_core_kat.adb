-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Known-answer test (KAT) for Schild_Fs_Core (SchildFS on-disk parsing core).
-- Verifies CRC32 (ISO-HDLC) against the standard test vector, and the
-- superblock / directory-entry serialization round-trips. Host-side:
-- run_fs_core_kat.sh.

with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces; use Interfaces;

with Schild_Fs_Core; use Schild_Fs_Core;

procedure Fs_Core_KAT is
   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      if Cond then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

begin
   -- 1. CRC-32/ISO-HDLC standard test vector: "123456789" -> 0xCBF43926.
   declare
      D : Block_Buf := [others => 0];
   begin
      D (0) := 16#31#;  -- '1'
      D (1) := 16#32#;  -- '2'
      D (2) := 16#33#;  -- '3'
      D (3) := 16#34#;  -- '4'
      D (4) := 16#35#;  -- '5'
      D (5) := 16#36#;  -- '6'
      D (6) := 16#37#;  -- '7'
      D (7) := 16#38#;  -- '8'
      D (8) := 16#39#;  -- '9'
      Check ("CRC32('123456789') = 0xCBF43926", CRC32 (D, 9) = 16#CBF43926#);
   end;

   -- 2. Superblock serialization round-trip.
   declare
      SB  : Superblock;
      SB2 : Superblock;
      Raw : Block_Buf;
   begin
      SB.Magic         := NVFS_Magic;
      SB.Version       := NVFS_Version;
      SB.Root_Dir_LBA  := 2;
      SB.Root_Entries  := 3;
      SB.Checksum      := 16#DEAD_BEEF#;
      SB.Generation    := 7;
      SB.Next_Free_LBA := 9;
      Superblock_To_Bytes (SB, Raw);
      Bytes_To_Superblock (Raw, SB2);
      Check ("superblock magic round-trip", SB2.Magic = NVFS_Magic);
      Check ("superblock version round-trip", SB2.Version = NVFS_Version);
      Check ("superblock root_entries round-trip", SB2.Root_Entries = 3);
      Check ("superblock checksum round-trip", SB2.Checksum = 16#DEAD_BEEF#);
      Check ("superblock generation round-trip", SB2.Generation = 7);
      Check ("superblock next_free_lba round-trip", SB2.Next_Free_LBA = 9);
   end;

   -- 3. Directory-entry serialization round-trip.
   declare
      Ent  : Dir_Entry;
      Ent2 : Dir_Entry;
      Raw  : Block_Buf := [others => 0];
   begin
      Ent.Name := [others => ' '];
      Ent.Name (1 .. 9) := "audit.log";
      Ent.Start_LBA := 42;
      Ent.Size      := 1234;
      Ent.Checksum  := 16#CAFE_BABE#;
      Dir_Entry_To_Bytes (Ent, Raw, 0);
      Bytes_To_Dir_Entry (Raw, 0, Ent2);
      Check ("dir-entry name round-trip", Ent2.Name = Ent.Name);
      Check ("dir-entry start_lba round-trip", Ent2.Start_LBA = 42);
      Check ("dir-entry size round-trip", Ent2.Size = 1234);
      Check ("dir-entry checksum round-trip", Ent2.Checksum = 16#CAFE_BABE#);
   end;

   Ada.Text_IO.Put_Line
     ("fs-core-kat: " & (if Failures = 0 then "PASS" else "FAIL")
      & " (" & Natural'Image (Failures) & " failures)");
   if Failures = 0 then
      Ada.Command_Line.Set_Exit_Status (0);
   else
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Fs_Core_KAT;
