pragma Spark_Mode (On);

package body Schild_Cet_Manager is

   procedure Activate_Cet_Protection
     (Sstk_Base : in     Interfaces.Unsigned_64;
      Passport  :    out Cet_Passport_Record;
      Success   :    out Boolean)
   is
   begin
      --  The shadow stack must be non-zero and 8-byte aligned.
      if Sstk_Base /= 0 and then (Sstk_Base and 16#7#) = 0 then
         Passport.Is_Shadow_Stack_Active := True;
         Passport.Is_Ib_Tracking_Active  := True;
         Success                         := True;
      else
         Passport := (Is_Shadow_Stack_Active => False, Is_Ib_Tracking_Active => False);
         Success  := False;
      end if;
   end Activate_Cet_Protection;

end Schild_Cet_Manager;
