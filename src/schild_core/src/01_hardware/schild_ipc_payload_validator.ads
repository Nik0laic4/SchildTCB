pragma Spark_Mode (On);

package Schild_Ipc_Payload_Validator is

   --  Largest valid payload (64 bytes).
   MAX_PAYLOAD_SIZE : constant := 64;
   
   type Type_Identifier is range 1 .. 255;
   type Length_Type is range 0 .. MAX_PAYLOAD_SIZE;

   --  A payload is valid when its (type, length) pair matches the schema.
   procedure Validate_Payload_Structure
     (Type_ID     : in     Type_Identifier;
      Length      : in     Length_Type;
      Is_Valid    :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Valid => (Type_ID, Length)),
     Post    => (if Is_Valid then
                   (Type_ID = 1 and Length = 8) or   --  Type 1: 8-byte payload.
                   (Type_ID = 2 and Length = 32) or  --  Type 2: 32-byte payload.
                   (Type_ID = 3 and Length = 64)     --  Type 3: 64-byte payload.
                 else
                   (Type_ID not in 1 .. 3) or
                   (Type_ID = 1 and Length /= 8) or
                   (Type_ID = 2 and Length /= 32) or
                   (Type_ID = 3 and Length /= 64));

end Schild_Ipc_Payload_Validator;
