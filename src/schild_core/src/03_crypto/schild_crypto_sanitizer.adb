package body Schild_Crypto_Sanitizer with
  SPARK_Mode => On
is

   procedure Purge_Sensitive_Data
     (Buffer : in out Crypto_Block_Buffer)
   is
   begin
      for I in Buffer'Range loop
         Buffer(I) := 0;

         pragma Loop_Invariant
           (for all J in Buffer'First .. I => Buffer(J) = 0);
      end loop;
   end Purge_Sensitive_Data;

end Schild_Crypto_Sanitizer;
