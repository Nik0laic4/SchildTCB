-- Schild TCB — provable ELF64 parsing core (H87).
-- Parses the ELF header + program headers of a daemon ELF image. The image is
-- trusted boot-time metadata (built by build_rt.sh), but the loader must still
-- bounds-check every header field (defense in depth: a malformed image must
-- fail safely, not OOB). Analogous to Schild_Fs_Core (audit H63).

with Interfaces; use Interfaces;

package Schild_Elf_Core with SPARK_Mode => On is

   type Byte is mod 2**8;

   --  ELF64 header is 64 bytes; one program header is 56 bytes.
   type Elf_Header_Buf is array (0 .. 63) of Byte;
   type Phdr_Buf is array (0 .. 55) of Byte;

   Elf_Magic : constant array (0 .. 3) of Byte := (16#7F#, 16#45#, 16#4C#, 16#46#);
   Elf_Class_64       : constant Byte := 2;
   Elf_Data_Lsb       : constant Byte := 1;
   Elf_Machine_X86_64 : constant Unsigned_16 := 62;
   Elf_Type_Exec      : constant Unsigned_16 := 2;
   PT_Load            : constant Unsigned_32 := 1;

   PF_X : constant Unsigned_32 := 1;
   PF_W : constant Unsigned_32 := 2;

   --  Parsed ELF header (only the fields the loader needs).
   type Elf64_Ehdr is record
      Class       : Byte := 0;
      Data        : Byte := 0;
      E_Type      : Unsigned_16 := 0;
      E_Machine   : Unsigned_16 := 0;
      E_Entry     : Unsigned_64 := 0;
      E_Phoff     : Unsigned_64 := 0;
      E_Phentsize : Unsigned_16 := 0;
      E_Phnum     : Unsigned_16 := 0;
   end record;

   --  Parsed program header (PT_LOAD fields).
   type Elf64_Phdr is record
      P_Type   : Unsigned_32 := 0;
      P_Flags  : Unsigned_32 := 0;
      P_Offset : Unsigned_64 := 0;
      P_Vaddr  : Unsigned_64 := 0;
      P_Filesz : Unsigned_64 := 0;
      P_Memsz  : Unsigned_64 := 0;
   end record;

   --  True when Raw is a valid ELF64, little-endian, x86_64, ET_EXEC image.
   function Is_Valid_Header (Raw : Elf_Header_Buf) return Boolean;

   procedure Parse_Header (Raw : Elf_Header_Buf; Hdr : out Elf64_Ehdr);

   procedure Parse_Phdr (Raw : Phdr_Buf; Ph : out Elf64_Phdr);

   function Is_Load (Ph : Elf64_Phdr) return Boolean is (Ph.P_Type = PT_Load);
   function Is_Executable (Ph : Elf64_Phdr) return Boolean is
     ((Ph.P_Flags and PF_X) /= 0);

end Schild_Elf_Core;
