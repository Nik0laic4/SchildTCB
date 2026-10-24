pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_64 for the PML4 address.

package Schild_Cr3_Loader is

   type Cr3_Context_Record is record
      Pml4_Physical_Address : Unsigned_64;
      Is_Tlb_Invalidated    : Boolean;
   end record;

   procedure Load_Cr3_Register
     (Pml4_Addr : in     Unsigned_64;
      Context   :    out Cr3_Context_Record;
      Success   :    out Boolean)
   with
     Global => null,
     Pre    => Pml4_Addr /= 0 and then (Pml4_Addr and 16#FFF#) = 0,
     Post   => (if Success then Context.Pml4_Physical_Address = Pml4_Addr and Context.Is_Tlb_Invalidated);

end Schild_Cr3_Loader;
