pragma Spark_Mode (On);

package body Schild_Ipc_Payload_Validator is

   procedure Validate_Payload_Structure
     (Type_ID     : in     Type_Identifier;
      Length      : in     Length_Type;
      Is_Valid    :    out Boolean)
   is
   begin
      if Type_ID = 1 and Length = 8 then
         Is_Valid := True;
      elsif Type_ID = 2 and Length = 32 then
         Is_Valid := True;
      elsif Type_ID = 3 and Length = 64 then
         Is_Valid := True;
      else
         Is_Valid := False;
      end if;
   end Validate_Payload_Structure;

end Schild_Ipc_Payload_Validator;
