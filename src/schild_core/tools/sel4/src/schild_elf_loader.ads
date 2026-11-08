-- Schild TCB — ELF child loader (H87).
-- Loads an ELF64 image into a daemon VSpace. The parsing is Schild_Elf_Core
-- (proved); this package is the seL4 mechanism (retype frames + map + copy),
-- so the body is SPARK_Mode => Off — trusted axiomatic, like Schild_Sel4_Syscall.

with Interfaces; use type Interfaces.Unsigned_64;
with Schild_Sel4_Syscall; use Schild_Sel4_Syscall;

package Schild_Elf_Loader with SPARK_Mode => On is

   -- Load an ELF64 image into a VSpace, retyping one 4K frame per page and
   -- copying the PT_LOAD contents (RX for executable segments, RW otherwise;
   -- the .bss tail beyond filesz is zeroed).
   --   Image_Base  : root-VA of the ELF image.
   --   Image_Size  : size of the image in bytes (used for header validation).
   --   VSpace      : daemon PML4 (root page table).
   --   Root_VSpace : the root task's VSpace (scratch mapping for the copy).
   --   RAM_UT      : untyped cap for retyping frames.
   --   CNode       : root CNode for the retype destination.
   --   Slot_Base   : first CSpace slot for the retyped frames (consumed 1/page).
   --   Status      : 0 on success, nonzero on the first failing syscall.
   --   Entry_Point : the ELF entry point (e_entry).
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
   with Pre => Image_Base /= 0 and Image_Size > 0 and VSpace > 0
               and Root_VSpace > 0 and RAM_UT > 0 and CNode > 0,
        Post => (if Status = 0 then Entry_Point /= 0);

end Schild_Elf_Loader;
