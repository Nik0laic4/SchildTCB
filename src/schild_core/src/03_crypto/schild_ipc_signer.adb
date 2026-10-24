pragma Spark_Mode (On);

package body Schild_Ipc_Signer is

   procedure Calculate_Payload_Signature
     (Payload   : in     Payload_Array;
      Signature :    out Word_64)
   is
      Current_Sign : Word_64;
   begin
      Current_Sign := Payload(1);
      
      --  Accumulate the XOR signature over the remaining payload words.
      Current_Sign := Current_Sign xor Payload(2);
      Current_Sign := Current_Sign xor Payload(3);
      Current_Sign := Current_Sign xor Payload(4);
      Current_Sign := Current_Sign xor Payload(5);
      Current_Sign := Current_Sign xor Payload(6);
      Current_Sign := Current_Sign xor Payload(7);
      Current_Sign := Current_Sign xor Payload(8);

      Signature := Current_Sign;
   end Calculate_Payload_Signature;

end Schild_Ipc_Signer;
