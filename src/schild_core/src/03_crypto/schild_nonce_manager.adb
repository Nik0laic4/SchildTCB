pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Nonce_Manager is

   procedure Verify_And_Update_Nonce
     (Incoming     : in     Unsigned_64;
      Nonce_Record : in out Nonce_Record_Type;
      Is_Valid     :    out Boolean)
   is
   begin
      if Nonce_Record.Is_Active and then Incoming > Nonce_Record.Current_Nonce then
         Nonce_Record.Current_Nonce := Incoming;
         Is_Valid                   := True;
      else
         Is_Valid                   := False;
      end if;
   end Verify_And_Update_Nonce;

end Schild_Nonce_Manager;
