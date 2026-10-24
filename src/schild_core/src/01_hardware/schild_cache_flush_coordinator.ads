with Interfaces; use Interfaces;

package Schild_Cache_Flush_Coordinator with
  SPARK_Mode => On
is

   type Target_Line_Address is new Interfaces.Unsigned_64;

   procedure Invalidate_Cache_Line
     (Line_Addr : in     Target_Line_Address;
      Success   :    out Boolean)
   with Pre => Line_Addr /= 0;

end Schild_Cache_Flush_Coordinator;
