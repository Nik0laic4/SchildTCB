-- Schild TCB — provable ELF64 parsing core (H87).

package body Schild_Elf_Core with SPARK_Mode => On is

   function LE16 (Raw : Elf_Header_Buf; Off : Natural) return Unsigned_16
     with Pre => Off <= Raw'Last - 1
   is
   begin
      return Unsigned_16 (Raw (Off)) or Shift_Left (Unsigned_16 (Raw (Off + 1)), 8);
   end LE16;

   function LE64 (Raw : Elf_Header_Buf; Off : Natural) return Unsigned_64
     with Pre => Off <= Raw'Last - 7
   is
   begin
      return Unsigned_64 (Raw (Off))
        or Shift_Left (Unsigned_64 (Raw (Off + 1)), 8)
        or Shift_Left (Unsigned_64 (Raw (Off + 2)), 16)
        or Shift_Left (Unsigned_64 (Raw (Off + 3)), 24)
        or Shift_Left (Unsigned_64 (Raw (Off + 4)), 32)
        or Shift_Left (Unsigned_64 (Raw (Off + 5)), 40)
        or Shift_Left (Unsigned_64 (Raw (Off + 6)), 48)
        or Shift_Left (Unsigned_64 (Raw (Off + 7)), 56);
   end LE64;

   function Ph_LE32 (Raw : Phdr_Buf; Off : Natural) return Unsigned_32
     with Pre => Off <= Raw'Last - 3
   is
   begin
      return Unsigned_32 (Raw (Off))
        or Shift_Left (Unsigned_32 (Raw (Off + 1)), 8)
        or Shift_Left (Unsigned_32 (Raw (Off + 2)), 16)
        or Shift_Left (Unsigned_32 (Raw (Off + 3)), 24);
   end Ph_LE32;

   function Ph_LE64 (Raw : Phdr_Buf; Off : Natural) return Unsigned_64
     with Pre => Off <= Raw'Last - 7
   is
   begin
      return Unsigned_64 (Raw (Off))
        or Shift_Left (Unsigned_64 (Raw (Off + 1)), 8)
        or Shift_Left (Unsigned_64 (Raw (Off + 2)), 16)
        or Shift_Left (Unsigned_64 (Raw (Off + 3)), 24)
        or Shift_Left (Unsigned_64 (Raw (Off + 4)), 32)
        or Shift_Left (Unsigned_64 (Raw (Off + 5)), 40)
        or Shift_Left (Unsigned_64 (Raw (Off + 6)), 48)
        or Shift_Left (Unsigned_64 (Raw (Off + 7)), 56);
   end Ph_LE64;

   function Is_Valid_Header (Raw : Elf_Header_Buf) return Boolean is
   begin
      return (for all I in 0 .. 3 => Raw (I) = Elf_Magic (I))
        and then Raw (4) = Elf_Class_64
        and then Raw (5) = Elf_Data_Lsb
        and then LE16 (Raw, 16) = Elf_Type_Exec
        and then LE16 (Raw, 18) = Elf_Machine_X86_64;
   end Is_Valid_Header;

   procedure Parse_Header (Raw : Elf_Header_Buf; Hdr : out Elf64_Ehdr) is
   begin
      Hdr.Class       := Raw (4);
      Hdr.Data        := Raw (5);
      Hdr.E_Type      := LE16 (Raw, 16);
      Hdr.E_Machine   := LE16 (Raw, 18);
      Hdr.E_Entry     := LE64 (Raw, 24);
      Hdr.E_Phoff     := LE64 (Raw, 32);
      Hdr.E_Phentsize := LE16 (Raw, 54);
      Hdr.E_Phnum     := LE16 (Raw, 56);
   end Parse_Header;

   procedure Parse_Phdr (Raw : Phdr_Buf; Ph : out Elf64_Phdr) is
   begin
      Ph.P_Type   := Ph_LE32 (Raw, 0);
      Ph.P_Flags  := Ph_LE32 (Raw, 4);
      Ph.P_Offset := Ph_LE64 (Raw, 8);
      Ph.P_Vaddr  := Ph_LE64 (Raw, 16);
      Ph.P_Filesz := Ph_LE64 (Raw, 32);
      Ph.P_Memsz  := Ph_LE64 (Raw, 40);
   end Parse_Phdr;

end Schild_Elf_Core;
