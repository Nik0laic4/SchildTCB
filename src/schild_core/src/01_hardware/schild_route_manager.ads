pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Route_Manager is

   type Route_Id_Type is range 1 .. 16;

   type Route_Entry_Record is record
      Gateway_IP : Unsigned_32;
      Is_Active  : Boolean;
   end record;

   type Route_Table_Matrix is array (Route_Id_Type) of Route_Entry_Record;

   procedure Lookup_Secure_Route
     (Target_IP   : in     Unsigned_32;
      Table       : in     Route_Table_Matrix;
      Route_Found :    out Boolean;
      Route_Idx   :    out Route_Id_Type)
   with
     Global => null,
     Post   => (if Route_Found then (for some I in Route_Id_Type => 
                  Table(I).Is_Active = True and Route_Idx = I));

end Schild_Route_Manager;
