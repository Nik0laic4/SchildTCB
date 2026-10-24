pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Sgx_Manager is

   type Enclave_Id_Type is mod 2**64;
   
   type Sgx_Passport_Record is record
      Enclave_ID : Enclave_Id_Type;
      Is_Enabled : Boolean;
   end record;

   procedure Initialize_Sgx_Enclave
     (Passport   : in     Sgx_Passport_Record;
      Success    :    out Boolean)
   with
     Global => null,
     Pre    => Passport.Enclave_ID /= 0;

end Schild_Sgx_Manager;
