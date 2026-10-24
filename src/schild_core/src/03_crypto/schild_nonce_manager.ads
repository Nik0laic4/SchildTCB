pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Nonce_Manager is

   type Nonce_Record_Type is record
      Current_Nonce : Unsigned_64;
      Is_Active     : Boolean;
   end record;

   procedure Verify_And_Update_Nonce
     (Incoming     : in     Unsigned_64;
      Nonce_Record : in out Nonce_Record_Type;
      Is_Valid     :    out Boolean)
   with
     Global => null,
     Post   => (if Is_Valid then Nonce_Record.Current_Nonce > Nonce_Record.Current_Nonce'Old
                and Nonce_Record.Current_Nonce = Incoming);

end Schild_Nonce_Manager;
