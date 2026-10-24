with Interfaces; use Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;

package Schild_Mls_Time_Manager with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Security_Timestamp is new Interfaces.Unsigned_64;
   
   type Time_Window_Record is record
      Start_Time : Security_Timestamp := 0;
      End_Time   : Security_Timestamp := 0;
      Is_Expired : Boolean := False;
   end record;

   procedure Validate_Access_Window
     (Window  : in out Time_Window_Record;
      Current : in     Security_Timestamp;
      Valid   :    out Boolean)
   with Post => (if Valid then not Window.Is_Expired);

end Schild_Mls_Time_Manager;
