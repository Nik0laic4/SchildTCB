pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Tr_Loader is

   procedure Load_Task_Register
     (Gdt      : in     Gdt_Table_Matrix;
      Passport :    out Tr_Loader_Passport;
      Success  :    out Boolean)
   is
   begin
      --  Verify the TSS descriptor is present and 64-bit available.
      if (Gdt (5).Access_Byte and 16#8F#) = 16#89# then
         Passport.Active_Selector := Tss_Gdt_Selector;
         Passport.Is_Activated    := True;
         Success                  := True;
      else
         Passport := (Active_Selector => 0, Is_Activated => False);
         Success  := False;
      end if;
   end Load_Task_Register;

end Schild_Tr_Loader;
