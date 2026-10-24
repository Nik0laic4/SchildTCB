pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Mmio_Mapper is

   procedure Map_Mmio_Region
     (Base_Phys_Addr : in     Unsigned_64;
      Passport       :    out Mmio_Passport_Record;
      Success        :    out Boolean)
   is
   begin
      if Base_Phys_Addr /= 0 then
         --  Map MMIO as uncached, supervisor-only.
         Passport.Mmio_Pte_Flags := 16#18#;
         Success                := True;
      else
         Passport := (Mmio_Pte_Flags => 0);
         Success  := False;
      end if;
   end Map_Mmio_Region;

end Schild_Mmio_Mapper;
