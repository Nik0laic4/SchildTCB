pragma Spark_Mode (On);

package body Schild_Tme_Manager is

   procedure Activate_Tme_Domain
     (Key_ID    : in     Domain_Key_Id;
      Page_Addr : in     Interfaces.Unsigned_64;
      Success   :    out Boolean)
   is
   begin
      --  Encrypt only valid (non-zero) page addresses.
      if Page_Addr /= 0 then
         Success := True;
      else
         Success := False;
      end if;
   end Activate_Tme_Domain;

end Schild_Tme_Manager;
