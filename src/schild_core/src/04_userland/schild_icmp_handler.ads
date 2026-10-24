with Interfaces; use Interfaces;

package Schild_Icmp_Handler with
  SPARK_Mode => On
is

   type Icmp_Type_Code is new Interfaces.Unsigned_8;
   -- 0 = Echo Reply, 8 = Echo Request

   type Icmp_Passport_Record is record
      Icmp_Type : Icmp_Type_Code := 8;
      Is_Valid  : Boolean := False;
   end record;

   procedure Process_Icmp_Echo
     (Raw_Len   : in     Interfaces.Unsigned_32;
      Passport  :    out Icmp_Passport_Record;
      Success   :    out Boolean)
   with Pre => Raw_Len >= 8 and Raw_Len <= 65507, --  ICMP echo length bounds (header + payload).
        Post => (if Success then Passport.Is_Valid);

end Schild_Icmp_Handler;
