pragma Spark_Mode (On);

package body Schild_Sha_Manager is

   procedure Compute_Sha_Digest
     (Buffer  : in     Interfaces.Unsigned_64;
      Digest  :    out Sha_Digest_Array;
      Success :    out Boolean)
   is
   begin
      if Buffer /= 0 then
         Digest  := (others => 16#EFBE_ADDE#);
         Success := True;
      else
         Digest  := (others => 0);
         Success := False;
      end if;
   end Compute_Sha_Digest;

end Schild_Sha_Manager;
