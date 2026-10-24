pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Cr3_Loader is

   procedure Load_Cr3_Register
     (Pml4_Addr : in     Unsigned_64;
      Context   :    out Cr3_Context_Record;
      Success   :    out Boolean)
   is
   begin
      --  Load only a non-zero, page-aligned PML4.
      if Pml4_Addr /= 0 and then (Pml4_Addr and 16#FFF#) = 0 then
         Context.Pml4_Physical_Address := Pml4_Addr;
         Context.Is_Tlb_Invalidated    := True;
         Success                       := True;
      else
         Context := (Pml4_Physical_Address => 0, Is_Tlb_Invalidated => False);
         Success := False;
      end if;
   end Load_Cr3_Register;

end Schild_Cr3_Loader;
