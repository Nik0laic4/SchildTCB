package body Schild_Ecdh_Manager with
  SPARK_Mode => On
is

   procedure Derive_Shared_Secret
     (Private_Key : in     Secret_Key_Array;
      Peer_Public : in     Secret_Key_Array;
      Secret      : in out Secret_Key_Array;
      Success     :    out Boolean)
   is
      Valid_Ok : Boolean;
   begin
      -- 1. Bitwise mixing ECDH keys
      for I in Secret'Range loop
         Secret(I) := Private_Key(I) xor Peer_Public(I);
         
         pragma Loop_Invariant
           (for all J in Secret'First .. I => 
              (if Private_Key(J) /= Peer_Public(J) then Secret(J) /= 0));
      end loop;

      -- 2. Check accumulated invariant (Zero-secret attack protection)
      Valid_Ok := False;
      for I in Secret'Range loop
         if Secret(I) /= 0 then
            Valid_Ok := True;
         end if;
         pragma Loop_Invariant (Valid_Ok = (for some J in Secret'First .. I => Secret(J) /= 0));
      end loop;

      Success := Valid_Ok;
   end Derive_Shared_Secret;

end Schild_Ecdh_Manager;
