-- Schild TCB — ELF child loader (H87). Body is the seL4 mechanism (Off).

with System;
with System.Storage_Elements;
with Interfaces; use type Interfaces.Unsigned_64;
with Schild_Elf_Core; use Schild_Elf_Core;
with Schild_Sel4_BootInfo;

package body Schild_Elf_Loader with SPARK_Mode => Off is
   use Schild_Sel4_Syscall;

   procedure Schild_Memcpy (Dst : Word; Src : Word; Len : Word);
   pragma Import (C, Schild_Memcpy, "schild_memcpy");

   procedure Schild_Memset_Zero (Dst : Word; Len : Word);
   pragma Import (C, Schild_Memset_Zero, "schild_memset_zero");

   function To_Word (A : System.Address) return Word is
      use System.Storage_Elements;
   begin
      return Word (To_Integer (A));
   end To_Word;

   --  Root-VSpace scratch VA: a reserved, otherwise-unused 4K-aligned address
   --  used to copy each freshly-retyped frame before it is mapped into the
   --  daemon VSpace. Must not collide with the image/IPC/shared/MMIO mappings.
   --  0x580000 is inside the image PT (0x400000..0x600000) and free (image ends
   --  0x468000; IPC=0x500000; shared DMA=0x520000).
   Scratch_VA : constant Word := 16#480000#;

   --  Load one PT_LOAD segment: retype a 4K frame per page, map it into the
   --  daemon VSpace (RX or RW), copy the file bytes via the scratch mapping,
   --  and zero the .bss tail (filesz .. memsz).
   function Load_Segment
     (Ph         : Elf64_Phdr;
      Image_Base : Word;
      VSpace     : Cap_Ref;
      Root_VSpace : Cap_Ref;
      RAM_UT     : Cap_Ref;
      CNode      : Cap_Ref;
      Frame_Slot : in out Cap_Ref)
     return Word
   is
      VStart : constant Word := Ph.P_Vaddr and (not 16#FFF#);
      VEnd   : constant Word := (Ph.P_Vaddr + Ph.P_Memsz + 16#FFF#) and (not 16#FFF#);
      VA     : Word := VStart;
      R      : Word;
   begin
      while VA < VEnd loop
         R := Retype_Object (RAM_UT, Object_Frame, 0, CNode, 0, Frame_Slot, 1);
         if R /= 0 then
            Put_String ("[ELF] Retype FAIL "); Schild_Sel4_BootInfo.Put_Hex (R);
            Put_String (ASCII.CR & ASCII.LF);
            return R;
         end if;

         --  Map into the daemon VSpace: RX for executable segments, RW otherwise.
         if Is_Executable (Ph) then
            R := Page_Map_Rights (Frame_Slot, VSpace, VA, 1);  -- RO + NX (exec via code seg)
         else
            R := Page_Map_Rights (Frame_Slot, VSpace, VA, 3);  -- RW + NX
         end if;
         if R /= 0 then
            Put_String ("[ELF] MapRights FAIL "); Schild_Sel4_BootInfo.Put_Hex (R);
            Put_String (ASCII.CR & ASCII.LF);
            return R;
         end if;

         --  Map into the root VSpace at the scratch VA so the copy can write it.
         R := Page_Map (Frame_Slot, Root_VSpace, Scratch_VA);
         if R /= 0 then
            Put_String ("[ELF] MapScratch FAIL "); Schild_Sel4_BootInfo.Put_Hex (R);
            Put_String (ASCII.CR & ASCII.LF);
            return R;
         end if;

         --  Copy the file bytes for this page (bounded by filesz), zero the rest.
         declare
            Off      : constant Word := VA - Ph.P_Vaddr;
            Copy_Len : Word := 0;
         begin
            if Off < Ph.P_Filesz then
               Copy_Len := Ph.P_Filesz - Off;
               if Copy_Len > 16#1000# then Copy_Len := 16#1000#; end if;
               Schild_Memcpy (Scratch_VA, Image_Base + Ph.P_Offset + Off, Copy_Len);
            end if;
            if Copy_Len < 16#1000# then
               Schild_Memset_Zero (Scratch_VA + Copy_Len, 16#1000# - Copy_Len);
            end if;
         end;

         Frame_Slot := Frame_Slot + 1;
         VA := VA + 16#1000#;
      end loop;
      return 0;
   end Load_Segment;

   procedure Load_Elf
     (Image_Base  : Word;
      Image_Size  : Word;
      VSpace      : Cap_Ref;
      Root_VSpace : Cap_Ref;
      RAM_UT      : Cap_Ref;
      CNode       : Cap_Ref;
      Slot_Base   : Cap_Ref;
      Status      : out Word;
      Entry_Point : out Word)
   is
      Hdr_Buf : Schild_Elf_Core.Elf_Header_Buf;
      Hdr     : Schild_Elf_Core.Elf64_Ehdr;
      Ph_Buf  : Schild_Elf_Core.Phdr_Buf;
      Ph      : Schild_Elf_Core.Elf64_Phdr;
      Frame_Slot : Cap_Ref := Slot_Base;
      R       : Word;
      I       : Word;
      Ph_Off  : Word;
   begin
      Status := 0;
      Entry_Point := 0;

      --  1. Validate + parse the header.
      Schild_Memcpy (To_Word (Hdr_Buf'Address), Image_Base, 64);
      if not Schild_Elf_Core.Is_Valid_Header (Hdr_Buf) then
         Status := 1;
         return;
      end if;
      Schild_Elf_Core.Parse_Header (Hdr_Buf, Hdr);
      Entry_Point := Hdr.E_Entry;

      --  2. Iterate program headers.
      I := 0;
      while I < Word (Hdr.E_Phnum) loop
         Ph_Off := Hdr.E_Phoff + I * Word (Hdr.E_Phentsize);
         Schild_Memcpy (To_Word (Ph_Buf'Address), Image_Base + Ph_Off, 56);
         Schild_Elf_Core.Parse_Phdr (Ph_Buf, Ph);
         if Schild_Elf_Core.Is_Load (Ph) then
            R := Load_Segment (Ph, Image_Base, VSpace, Root_VSpace,
                               RAM_UT, CNode, Frame_Slot);
            if R /= 0 then
               Status := R;
               return;
            end if;
         end if;
         I := I + 1;
      end loop;

      Status := 0;
   end Load_Elf;

end Schild_Elf_Loader;
