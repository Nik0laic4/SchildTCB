pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned types for the GDT/TSS selector.

package Schild_Tr_Loader is

   Tss_Gdt_Selector : constant Unsigned_16 := 16#0028#;

   type Gdt_Entry_Record is record
      Access_Byte : Unsigned_8;
   end record;

   type Gdt_Table_Matrix is array (1 .. 7) of Gdt_Entry_Record;

   type Tr_Loader_Passport is record
      Active_Selector : Unsigned_16;
      Is_Activated    : Boolean;
   end record;

   procedure Load_Task_Register
     (Gdt      : in     Gdt_Table_Matrix;
      Passport :    out Tr_Loader_Passport;
      Success  :    out Boolean)
   with
     Global => null,
     Pre    => (Gdt (5).Access_Byte and 16#8F#) = 16#89#,
     Post   => (if Success then Passport.Is_Activated 
                and Passport.Active_Selector = Tss_Gdt_Selector);

end Schild_Tr_Loader;
