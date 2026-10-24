-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- Schild TCB Stage 7.9: SPARK Proofs — body

package body Schild_Net_Spark_Proofs with SPARK_Mode => On is

   function IPv4_Checksum (H : Ipv4_Header) return Unsigned_16
   is
      Sum : Unsigned_32 := 0;
      W   : Unsigned_16;
      use type Unsigned_32;
   begin
      -- Word 0: V_IHL + DSCP
      W := Shift_Left (Unsigned_16 (H.V_IHL), 8) or Unsigned_16 (H.DSCP);
      Sum := Sum + Unsigned_32 (W);
      -- Word 1: Total_Len
      Sum := Sum + Unsigned_32 (H.Len);
      -- Word 2: Ident
      Sum := Sum + Unsigned_32 (H.Ident);
      -- Word 3: Flags_Frag
      Sum := Sum + Unsigned_32 (H.Frag);
      -- Word 4: TTL + Proto
      W := Shift_Left (Unsigned_16 (H.TTL), 8) or Unsigned_16 (H.Proto);
      Sum := Sum + Unsigned_32 (W);
      -- Words 6-7: Src IP
      Sum := Sum + Unsigned_32 (Shift_Right (H.Src, 16) and 65535);
      Sum := Sum + Unsigned_32 (H.Src and 65535);
      -- Words 8-9: Dst IP
      Sum := Sum + Unsigned_32 (Shift_Right (H.Dst, 16) and 65535);
      Sum := Sum + Unsigned_32 (H.Dst and 65535);

      -- Fold 32-bit to 16-bit (RFC 1071, max 2 iterations)
      while Sum > 65535 loop
         pragma Loop_Invariant (Sum <= 16#0008_FFF7#);   -- 9 words * 0xFFFF = 589815 max
         pragma Loop_Variant (Decreases => Sum);
         Sum := (Sum and 65535) + Shift_Right (Sum, 16);
      end loop;

      return Unsigned_16 (not Sum and 65535);
   end IPv4_Checksum;

   function Valid_Transition
     (Old_State, New_State : Tcp_State; Syn_Flag, Ack_Flag, Fin_Flag : Boolean)
      return Boolean
   is
      use type Tcp_State;
   begin
      case Old_State is
         when CLOSED =>
            return New_State = SYN_RCVD and Syn_Flag;
         when LISTEN =>
            return New_State = SYN_RCVD and Syn_Flag;
         when SYN_RCVD =>
            return New_State = ESTABLISHED and Ack_Flag;
         when ESTABLISHED =>
            return (New_State = CLOSE_WAIT and Fin_Flag) or
                   (New_State = ESTABLISHED and Ack_Flag);
         when CLOSE_WAIT =>
            return New_State = LAST_ACK;
         when LAST_ACK =>
            return New_State = CLOSED and Ack_Flag;
      end case;
   end Valid_Transition;

   procedure Prove_Buffer_Safety
     (Packet_Len : in Natural; Valid : out Boolean)
   is
   begin
      Valid := (Packet_Len >= 14);
   end Prove_Buffer_Safety;

end Schild_Net_Spark_Proofs;
