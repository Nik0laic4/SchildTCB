with Interfaces; use Interfaces;
with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package Schild_Frame_Deallocator with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   --  Alias for the physical page address.
   subtype Physical_Page_Address is Schild_Mmu_Overseer.Physical_Address;
   
   type Frame_Deallocate_Passport is record
      Physical_Address : Physical_Page_Address := 0;
      Bitmap_Block     : Interfaces.Unsigned_64 := 0;
      Bit_Position     : Standard.Integer := 0;
      Is_Freed         : Boolean := False;
   end record;

   procedure Safe_Deallocate_Frame
     (Passport : in out Frame_Deallocate_Passport;
      Success  :    out Boolean)
   with Pre => Passport.Physical_Address /= 0,
        Post => (if Success then Passport.Is_Freed);

end Schild_Frame_Deallocator;
