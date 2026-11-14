-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Known-answer test (KAT) for Schild_Elf_Core (H87 ELF64 parser).
-- Verifies Is_Valid_Header (magic/class/data/type/machine) + Parse_Header +
-- Parse_Phdr (PT_LOAD fields). Host-side: run via run_elf_kat.sh.

with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces; use Interfaces;

with Schild_Elf_Core; use Schild_Elf_Core;

procedure Elf_KAT is
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

   procedure Put_LE16 (Raw : in out Elf_Header_Buf; Off : Natural; V : Unsigned_16) is
   begin
      Raw (Off)     := Byte (V mod 256);
      Raw (Off + 1) := Byte ((V / 256) mod 256);
   end Put_LE16;

   procedure Put_LE64 (Raw : in out Elf_Header_Buf; Off : Natural; V : Unsigned_64) is
   begin
      for I in 0 .. 7 loop
         Raw (Off + I) := Byte ((V / (2 ** (8 * I))) mod 256);
      end loop;
   end Put_LE64;

   procedure Put_Ph_LE32 (Raw : in out Phdr_Buf; Off : Natural; V : Unsigned_32) is
   begin
      for I in 0 .. 3 loop
         Raw (Off + I) := Byte ((V / (2 ** (8 * I))) mod 256);
      end loop;
   end Put_Ph_LE32;

   procedure Put_Ph_LE64 (Raw : in out Phdr_Buf; Off : Natural; V : Unsigned_64) is
   begin
      for I in 0 .. 7 loop
         Raw (Off + I) := Byte ((V / (2 ** (8 * I))) mod 256);
      end loop;
   end Put_Ph_LE64;

   function Valid_Header return Elf_Header_Buf is
      Raw : Elf_Header_Buf := [others => 0];
   begin
      Raw (0) := 16#7F#;
      Raw (1) := 16#45#;  -- 'E'
      Raw (2) := 16#4C#;  -- 'L'
      Raw (3) := 16#46#;  -- 'F'
      Raw (4) := Elf_Class_64;      -- 2
      Raw (5) := Elf_Data_Lsb;      -- 1
      Raw (6) := 1;                 -- ELF version
      Put_LE16 (Raw, 16, Elf_Type_Exec);      -- ET_EXEC
      Put_LE16 (Raw, 18, Elf_Machine_X86_64); -- x86_64
      Put_LE64 (Raw, 24, 16#400000#);         -- e_entry
      Put_LE64 (Raw, 32, 16#40#);             -- e_phoff
      Put_LE16 (Raw, 54, 56);                 -- e_phentsize
      Put_LE16 (Raw, 56, 2);                  -- e_phnum
      return Raw;
   end Valid_Header;

   Hdr  : Elf64_Ehdr;
   Ph   : Elf64_Phdr;
   Raw  : Elf_Header_Buf;
   PRaw : Phdr_Buf;
begin
   -- 1. Valid header parses to the expected fields.
   Raw := Valid_Header;
   Check ("Is_Valid_Header (valid) = True", Is_Valid_Header (Raw));
   Parse_Header (Raw, Hdr);
   Check ("Parse_Header entry = 0x400000", Hdr.E_Entry = 16#400000#);
   Check ("Parse_Header phoff = 0x40", Hdr.E_Phoff = 16#40#);
   Check ("Parse_Header phentsize = 56", Hdr.E_Phentsize = 56);
   Check ("Parse_Header phnum = 2", Hdr.E_Phnum = 2);

   -- 2. Bad magic.
   Raw := Valid_Header; Raw (0) := 0;
   Check ("bad magic -> not valid", not Is_Valid_Header (Raw));

   -- 3. Bad class (ELF32).
   Raw := Valid_Header; Raw (4) := 1;
   Check ("bad class -> not valid", not Is_Valid_Header (Raw));

   -- 4. Bad data (MSB).
   Raw := Valid_Header; Raw (5) := 2;
   Check ("bad data -> not valid", not Is_Valid_Header (Raw));

   -- 5. Bad type (ET_REL).
   Raw := Valid_Header; Put_LE16 (Raw, 16, 1);
   Check ("bad type -> not valid", not Is_Valid_Header (Raw));

   -- 6. Bad machine.
   Raw := Valid_Header; Put_LE16 (Raw, 18, 0);
   Check ("bad machine -> not valid", not Is_Valid_Header (Raw));

   -- 7. PT_LOAD (RX) program header.
   PRaw := [others => 0];
   Put_Ph_LE32 (PRaw, 0, PT_Load);      -- 1
   Put_Ph_LE32 (PRaw, 4, PF_X);         -- executable
   Put_Ph_LE64 (PRaw, 16, 16#400000#);  -- p_vaddr
   Put_Ph_LE64 (PRaw, 32, 16#1000#);    -- p_filesz
   Put_Ph_LE64 (PRaw, 40, 16#1000#);    -- p_memsz
   Parse_Phdr (PRaw, Ph);
   Check ("Parse_Phdr type = PT_LOAD", Ph.P_Type = PT_Load);
   Check ("Parse_Phdr vaddr = 0x400000", Ph.P_Vaddr = 16#400000#);
   Check ("Parse_Phdr filesz = 0x1000", Ph.P_Filesz = 16#1000#);
   Check ("Is_Load (PT_LOAD) = True", Is_Load (Ph));
   Check ("Is_Executable (PF_X) = True", Is_Executable (Ph));

   -- 8. Non-PT_LOAD program header (PT_NOTE).
   PRaw := [others => 0];
   Put_Ph_LE32 (PRaw, 0, 4);   -- PT_NOTE
   Parse_Phdr (PRaw, Ph);
   Check ("Is_Load (PT_NOTE) = False", not Is_Load (Ph));

   Ada.Text_IO.Put_Line
     ("elf-kat: " & (if Failures = 0 then "PASS" else "FAIL")
      & " (" & Natural'Image (Failures) & " failures)");
   if Failures = 0 then
      Ada.Command_Line.Set_Exit_Status (0);
   else
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Elf_KAT;
