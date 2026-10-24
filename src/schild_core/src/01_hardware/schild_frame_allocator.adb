with Interfaces;              use Interfaces;
with Schild_Mmu_Overseer;     use Schild_Mmu_Overseer;
with Schild_Frame_Deallocator; use Schild_Frame_Deallocator;

package body Schild_Frame_Allocator with
  SPARK_Mode => Off --  Real bitmap allocator over a mutable global arena.
is

   --  Frame arena: 4 KiB frames starting at 2 MiB, 64 MiB total (16 384 frames).
   Frame_Base  : constant Physical_Address := 16#0000_0000_0020_0000#;
   Frame_Count : constant := 16_384;
   Words       : constant := Frame_Count / 64;

   Bitmap    : array (0 .. Words - 1) of Unsigned_64 := (others => 0);
   Next_Hint : Integer := 0;

   procedure Allocate_Physical_Frame
     (Passport : in out Frame_Deallocate_Passport;
      Success  :    out Boolean)
   is
      Bit : Integer := -1;
   begin
      Success := False;

      --  Linear scan for the first free bit, wrapping once from Next_Hint.
      for I in 0 .. Frame_Count - 1 loop
         declare
            Idx : constant Integer := (Next_Hint + I) mod Frame_Count;
            W   : constant Integer := Idx / 64;
            B   : constant Integer := Idx mod 64;
         begin
            if (Bitmap (W) and Shift_Left (Unsigned_64'(1), B)) = 0 then
               Bit := Idx;
               exit;
            end if;
         end;
      end loop;

      if Bit < 0 then
         return;  --  arena exhausted
      end if;

      --  Mark the frame allocated (single word, no aliasing).
      Bitmap (Bit / 64) := Bitmap (Bit / 64) or Shift_Left (Unsigned_64'(1), Bit mod 64);
      Next_Hint := (Bit + 1) mod Frame_Count;

      Passport.Physical_Address := Frame_Base + Physical_Address (Bit) * 4096;
      Passport.Bitmap_Block     := Unsigned_64 (Bit / 64);
      Passport.Bit_Position     := Bit mod 64;
      Passport.Is_Freed         := False;
      Success := True;
   end Allocate_Physical_Frame;

end Schild_Frame_Allocator;
