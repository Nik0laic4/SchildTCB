pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_16/Unsigned_32/Unsigned_64 for the TSS layout.

package Schild_Tss_Layout is

   type Tss_Structure_Array is array (1 .. 4) of Unsigned_32;

   type Tss_Layout_Passport is record
      Rsp0_Low_Bound  : Unsigned_32;
      Rsp0_High_Bound : Unsigned_32;
   end record;

   procedure Build_Tss_Layout
     (Rsp0_Addr  : in     Unsigned_64;
      Tss_Struct :    out Tss_Structure_Array;
      Passport   :    out Tss_Layout_Passport;
      Success    :    out Boolean)
   with
     Global => null,
     Pre    => Rsp0_Addr /= 0 and then (Rsp0_Addr and 16#0F#) = 0,
     Post   => (if Success then 
                  Tss_Struct (2) = Passport.Rsp0_Low_Bound and 
                  Tss_Struct (3) = Passport.Rsp0_High_Bound);

end Schild_Tss_Layout;
