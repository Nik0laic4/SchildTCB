pragma Spark_Mode (On);

package body Schild_Sgx_Manager is

   procedure Initialize_Sgx_Enclave
     (Passport   : in     Sgx_Passport_Record;
      Success    :    out Boolean)
   is
   begin
      --  Only an enabled enclave with a valid id is usable.
      if Passport.Is_Enabled and then Passport.Enclave_ID /= 0 then
         Success := True;
      else
         Success := False;
      end if;
   end Initialize_Sgx_Enclave;

end Schild_Sgx_Manager;
