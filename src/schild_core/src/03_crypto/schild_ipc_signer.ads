pragma Spark_Mode (On);

package Schild_Ipc_Signer is

   type Block_Index is range 1 .. 8;
   type Word_64 is mod 2**64;
   type Payload_Array is array (Block_Index) of Word_64;

   --  Fold the eight payload words into one 64-bit integrity signature (XOR).
   procedure Calculate_Payload_Signature
     (Payload   : in     Payload_Array;
      Signature :    out Word_64)
   with
     Global => null,
     Depends => (Signature => Payload),
     Post => Signature = (Payload(1) xor Payload(2) xor Payload(3) xor Payload(4) xor
                          Payload(5) xor Payload(6) xor Payload(7) xor Payload(8));

end Schild_Ipc_Signer;
