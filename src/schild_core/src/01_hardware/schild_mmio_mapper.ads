pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned types for MMIO flags.

package Schild_Mmio_Mapper is

   type Mmio_Passport_Record is record
      Mmio_Pte_Flags : Unsigned_64;
   end record;

   procedure Map_Mmio_Region
     (Base_Phys_Addr : in     Unsigned_64;
      Passport       :    out Mmio_Passport_Record;
      Success        :    out Boolean)
   with
     Global => null,
     Pre    => Base_Phys_Addr /= 0,
     Post   => (if Success then (Passport.Mmio_Pte_Flags and 16#18#) = 16#18#);

end Schild_Mmio_Mapper;
