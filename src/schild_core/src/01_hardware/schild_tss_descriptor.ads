pragma Spark_Mode (On);

with Interfaces; 
use Interfaces;

package Schild_Tss_Descriptor is

   type Tss_Table_Array is array (1 .. 5) of Unsigned_8;

   procedure Validate_Tss_Entry
     (Tss_Addr   : in     Unsigned_64;
      Tss_Size   : in     Unsigned_32;
      Table      : in     Tss_Table_Array;
      Is_Success :    out Boolean)
   with
     Global => null,
     Pre    => Tss_Addr /= 0 and Tss_Size >= 104,
     Post   => Is_Success = ((Table(5) and 16#8F#) = 16#89#);

end Schild_Tss_Descriptor;
