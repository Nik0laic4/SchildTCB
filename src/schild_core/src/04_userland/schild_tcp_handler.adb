-- Schild TCB Stage 7.9: TCP Handler — body
with System; with Interfaces;
with Schild_Uart_Driver; with Schild_Ipv4_Handler;

package body Schild_Tcp_Handler with SPARK_Mode => On, Refined_State => (Entropy_State => Entropy_Counter) is
   use Interfaces;

   procedure C_Putln (Addr : System.Address; Len : Integer) with Global => null;
   pragma Import (C, C_Putln, "schild_uart_putln");

   --  Hardware timestamp counter (RDTSC): entropy source for the ISN and the
   --  clock for TCP connection idle timeouts.
   function C_Rdtsc return Unsigned_64 with Global => null;
   pragma Import (C, C_Rdtsc, "schild_rdtsc");

   --  Monotonic per-boot counter mixed into the ISN (RDTSC low bits + counter).
   Entropy_Counter : Unsigned_32 := 0;

   --  Idle timeout: a connection is recycled when no segment is seen for
   --  ~30 s (assumes a ~2 GHz invariant TSC), preventing SYN-flood exhaustion.
   TCP_Idle_Timeout_Cycles : constant Unsigned_64 := 60_000_000_000;

   procedure Generate_Isn (Result : out Unsigned_32) is
   begin
      Entropy_Counter := Entropy_Counter + 1;
      Result := Unsigned_32 (C_Rdtsc mod 2**32) xor Entropy_Counter;
   end Generate_Isn;

   procedure Expire_Stale (Table : in out Tcp_Conn_Table) is
      Now : constant Unsigned_64 := C_Rdtsc;
   begin
      for I in Table'Range loop
         if Table (I).State /= CLOSED
           and then Table (I).Last_Active /= 0
           and then Now - Table (I).Last_Active > TCP_Idle_Timeout_Cycles
         then
            Table (I).State := CLOSED;
         end if;
      end loop;
   end Expire_Stale;

   procedure Parse_Tcp (Raw : in Byte_Array; Header : out Tcp_Header; Valid : out Boolean) is
   begin
      Valid := False;
      Header := (others => <>);  -- default-init so early return leaves no uninit field
      --  Runtime guard (the Pre condition is not enforced with SPARK_Mode Off
      --  and no -gnata): a TCP header is at least 20 bytes. Reject malformed
      --  short segments instead of reading out of bounds.
      if Raw'Length < 20 then
         return;
      end if;
      Header.Src_Port := Shift_Left (Unsigned_16 (Raw (Raw'First)), 8)
                          or Unsigned_16 (Raw (Raw'First + 1));
      Header.Dst_Port := Shift_Left (Unsigned_16 (Raw (Raw'First + 2)), 8)
                          or Unsigned_16 (Raw (Raw'First + 3));
      Header.Seq_Num  := Shift_Left (Unsigned_32 (Raw (Raw'First + 4)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 5)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 6)), 8)
        or Unsigned_32 (Raw (Raw'First + 7));
      Header.Ack_Num  := Shift_Left (Unsigned_32 (Raw (Raw'First + 8)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 9)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 10)), 8)
        or Unsigned_32 (Raw (Raw'First + 11));
      Header.Data_Off := Raw (Raw'First + 12);
      Header.Flags    := Raw (Raw'First + 13);
      Header.Window   := Shift_Left (Unsigned_16 (Raw (Raw'First + 14)), 8)
                          or Unsigned_16 (Raw (Raw'First + 15));
      Header.Checksum := Shift_Left (Unsigned_16 (Raw (Raw'First + 16)), 8)
                          or Unsigned_16 (Raw (Raw'First + 17));
      Header.Urgent_Ptr := Shift_Left (Unsigned_16 (Raw (Raw'First + 18)), 8)
                            or Unsigned_16 (Raw (Raw'First + 19));
      Valid := True;
   end Parse_Tcp;

   function Compute_Tcp_Checksum (Src_IP, Dst_IP : Unsigned_32; Tcp_Hdr : Tcp_Header;
                                   Payload : Byte_Array) return Unsigned_16
   is
      Hdr_Len : constant Unsigned_16 := (Unsigned_16 (Tcp_Hdr.Data_Off) / 16) * 4;
      Tcp_Len : constant Unsigned_16 := Hdr_Len + Unsigned_16 (Payload'Length);
      Sum : Unsigned_32 := 0;
      W   : Unsigned_16;
      use type Unsigned_32;
   begin
      -- Pseudo-header (high/low 16-bit words via modular arithmetic).
      Sum := Sum + (Src_IP / 65536);
      Sum := Sum + (Src_IP mod 65536);
      Sum := Sum + (Dst_IP / 65536);
      Sum := Sum + (Dst_IP mod 65536);
      Sum := Sum + 6;  -- Protocol TCP
      Sum := Sum + Unsigned_32 (Tcp_Len);

      -- TCP header words.
      Sum := Sum + Unsigned_32 (Tcp_Hdr.Src_Port);
      Sum := Sum + Unsigned_32 (Tcp_Hdr.Dst_Port);
      Sum := Sum + (Tcp_Hdr.Seq_Num / 65536);
      Sum := Sum + (Tcp_Hdr.Seq_Num mod 65536);
      Sum := Sum + (Tcp_Hdr.Ack_Num / 65536);
      Sum := Sum + (Tcp_Hdr.Ack_Num mod 65536);
      W := Shift_Left (Unsigned_16 (Tcp_Hdr.Data_Off), 8) or Unsigned_16 (Tcp_Hdr.Flags);
      Sum := Sum + Unsigned_32 (W);
      Sum := Sum + Unsigned_32 (Tcp_Hdr.Window);
      Sum := Sum + Unsigned_32 (Tcp_Hdr.Urgent_Ptr);

      -- Payload.
      declare
         I : Integer := Payload'First;
      begin
         while I < Payload'Last loop
            pragma Loop_Variant (Increases => I);
            pragma Loop_Invariant (I >= Payload'First);
            pragma Loop_Invariant (I <= Payload'Last);
            W := Shift_Left (Unsigned_16 (Payload (I)), 8)
                 or Unsigned_16 (Payload (I + 1));
            Sum := Sum + Unsigned_32 (W);
            I := I + 2;
         end loop;
         if I = Payload'Last then
            Sum := Sum + Unsigned_32 (Shift_Left (Unsigned_16 (Payload (I)), 8));
         end if;
      end;

      -- RFC 1071 fold (modular): (Sum mod 65536) + (Sum / 65536).
      while Sum > 65535 loop
         pragma Loop_Variant (Decreases => Sum);
         Sum := (Sum mod 65536) + (Sum / 65536);
      end loop;
      -- One's complement of the low 16 bits: 65535 - (Sum mod 65536).
      return Unsigned_16 (65535 - (Sum mod 65536));
   end Compute_Tcp_Checksum;

   function Compute_Tcp_Checksum_Raw (Src_IP, Dst_IP : Unsigned_32;
      Seg : Byte_Array; Csum_Off : Integer) return Unsigned_16
   is
      Sum : Unsigned_32 := 0;
      W   : Unsigned_16;
      I   : Integer := Seg'First;
      use type Unsigned_32;
   begin
      -- Pseudo-header (RFC 793): addresses, zero, protocol, TCP length.
      Sum := Sum + (Src_IP / 65536);
      Sum := Sum + (Src_IP mod 65536);
      Sum := Sum + (Dst_IP / 65536);
      Sum := Sum + (Dst_IP mod 65536);
      Sum := Sum + 6;
      Sum := Sum + Unsigned_32 (Seg'Length);
      -- Sum the whole segment (header + options + payload) with the checksum
      -- field treated as zero, so option-bearing headers validate correctly.
      while I <= Seg'Last loop
         pragma Loop_Variant (Increases => I);
         pragma Loop_Invariant (I >= Seg'First);
         if I = Csum_Off then
            I := I + 2;  -- skip the 16-bit checksum field
         elsif I + 1 <= Seg'Last then
            W := Shift_Left (Unsigned_16 (Seg (I)), 8) or Unsigned_16 (Seg (I + 1));
            Sum := Sum + Unsigned_32 (W);
            I := I + 2;
         else
            Sum := Sum + Unsigned_32 (Shift_Left (Unsigned_16 (Seg (I)), 8));
            I := I + 1;
         end if;
      end loop;
      while Sum > 65535 loop
         pragma Loop_Variant (Decreases => Sum);
         Sum := (Sum mod 65536) + (Sum / 65536);
      end loop;
      return Unsigned_16 (65535 - (Sum mod 65536));
   end Compute_Tcp_Checksum_Raw;

   function Validate_Tcp_Checksum (Src_IP, Dst_IP : Unsigned_32;
      Tcp_Seg : Byte_Array) return Boolean
   is
      Csum_Off : constant Integer := Tcp_Seg'First + 16;
      Received : constant Unsigned_16 :=
        Shift_Left (Unsigned_16 (Tcp_Seg (Csum_Off)), 8)
          or Unsigned_16 (Tcp_Seg (Csum_Off + 1));
      Expected : constant Unsigned_16 :=
        Compute_Tcp_Checksum_Raw (Src_IP, Dst_IP, Tcp_Seg, Csum_Off);
   begin
      return Expected = Received;
   end Validate_Tcp_Checksum;

   procedure Build_Tcp_Reply
     (Conn : in Tcp_Connection; Flags : Unsigned_8; Seq, Ack : Unsigned_32;
      Payload : Byte_Array; Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16)
   is
      Idx : Integer := Reply_Buf'First;
      Hdr : Tcp_Header;
      procedure Put_U8 (V : Unsigned_8) is begin Reply_Buf (Idx) := V; Idx := Idx + 1; end Put_U8;
      procedure Put_U16 (V : Unsigned_16) is begin
         Reply_Buf (Idx) := Unsigned_8 (Shift_Right (V, 8) and 255);
         Reply_Buf (Idx + 1) := Unsigned_8 (V and 255); Idx := Idx + 2;
      end Put_U16;
      procedure Put_U32 (V : Unsigned_32) is begin
         Put_U16 (Unsigned_16 (Shift_Right (V, 16) and 65535));
         Put_U16 (Unsigned_16 (V and 65535));
      end Put_U32;
      use type Unsigned_32;
   begin
      Hdr.Src_Port   := HTTP_Port;
      Hdr.Dst_Port   := Conn.Client_Port;
      Hdr.Seq_Num    := Seq;
      Hdr.Ack_Num    := Ack;
      Hdr.Data_Off   := 16#50#;
      Hdr.Flags      := Flags;
      Hdr.Window     := 1460;
      Hdr.Urgent_Ptr := 0;
      Hdr.Checksum   := Compute_Tcp_Checksum (Our_IP, Conn.Client_IP, Hdr, Payload);

      Put_U16 (Hdr.Src_Port);
      Put_U16 (Hdr.Dst_Port);
      Put_U32 (Hdr.Seq_Num);
      Put_U32 (Hdr.Ack_Num);
      Put_U8  (Hdr.Data_Off);
      Put_U8  (Hdr.Flags);
      Put_U16 (Hdr.Window);
      Put_U16 (Hdr.Checksum);
      Put_U16 (Hdr.Urgent_Ptr);

      for J in Payload'Range loop
         pragma Loop_Invariant (Idx - Idx'Loop_Entry = J - Payload'First);
         Put_U8 (Payload (J));
      end loop;
      Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
   end Build_Tcp_Reply;

   procedure Process_Tcp
     (Conn : in out Tcp_Connection; Tcp_Hdr : in Tcp_Header;
      Src_IP : in Unsigned_32; Src_MAC : in Unsigned_8_Array_6;
      Payload : in Byte_Array; Reply_Buf : out Byte_Array;
      Reply_Len : out Unsigned_16; Has_Data : out Boolean)
   is
      use type Unsigned_16; use type Unsigned_32;
   begin
      Has_Data := False;
      Reply_Len := 0;

      if Tcp_Hdr.Dst_Port /= HTTP_Port then return; end if;

      --  Refresh the idle-timeout timestamp on every accepted segment.
      Conn.Last_Active := C_Rdtsc;

      -- RST handling: close connection
      if (Tcp_Hdr.Flags and Flag_RST) /= 0 then
         Conn.State := CLOSED; return;
      end if;

      case Conn.State is
         when CLOSED | LISTEN =>
            if (Tcp_Hdr.Flags and Flag_SYN) /= 0 then
               Conn.State := SYN_RCVD;
               Conn.Client_IP := Src_IP;
               Conn.Client_Port := Tcp_Hdr.Src_Port;
               Conn.Client_MAC := Src_MAC;
               Conn.Client_Seq := Tcp_Hdr.Seq_Num;
               Generate_Isn (Conn.Our_Seq);
               Build_Tcp_Reply (Conn, Flag_SYN or Flag_ACK,
                 Conn.Our_Seq, Conn.Client_Seq + 1,
                 (0 .. -1 => 0), Reply_Buf, Reply_Len);
               -- SYN consumes one sequence number: advance past it so the
               -- data/ACK segments carry the correct Seq_Num.
               Conn.Our_Seq := Conn.Our_Seq + 1;
            end if;

         when SYN_RCVD =>
            if (Tcp_Hdr.Flags and Flag_ACK) /= 0 then
               Conn.State := ESTABLISHED;
               Conn.Client_Seq := Tcp_Hdr.Seq_Num;
            end if;

         when ESTABLISHED =>
            if (Tcp_Hdr.Flags and Flag_FIN) /= 0 then
               Conn.State := LAST_ACK;
               Build_Tcp_Reply (Conn, Flag_FIN or Flag_ACK,
                 Conn.Our_Seq, Tcp_Hdr.Seq_Num + 1,
                 (0 .. -1 => 0), Reply_Buf, Reply_Len);
            elsif Payload'Length > 0 then
               Conn.Client_Seq := Tcp_Hdr.Seq_Num + Unsigned_32 (Payload'Length);
               Build_Tcp_Reply (Conn, Flag_ACK,
                 Conn.Our_Seq, Conn.Client_Seq,
                 (0 .. -1 => 0), Reply_Buf, Reply_Len);
               Has_Data := True;
            end if;

         when LAST_ACK =>
            if (Tcp_Hdr.Flags and Flag_ACK) /= 0 then
               Conn.State := CLOSED;
            end if;

         when FIN_WAIT_1 =>
            if (Tcp_Hdr.Flags and Flag_ACK) /= 0 then
               Conn.State := FIN_WAIT_2;
            elsif (Tcp_Hdr.Flags and Flag_FIN) /= 0 then
               --  Simultaneous close: peer FIN'd before ACKing our FIN.
               Conn.State := CLOSED;
               Build_Tcp_Reply (Conn, Flag_ACK, Conn.Our_Seq,
                 Tcp_Hdr.Seq_Num + 1, (0 .. -1 => 0), Reply_Buf, Reply_Len);
            end if;

         when FIN_WAIT_2 =>
            if (Tcp_Hdr.Flags and Flag_FIN) /= 0 then
               Conn.State := CLOSED;
               Build_Tcp_Reply (Conn, Flag_ACK, Conn.Our_Seq,
                 Tcp_Hdr.Seq_Num + 1, (0 .. -1 => 0), Reply_Buf, Reply_Len);
            end if;

         when others => null;
      end case;
   end Process_Tcp;

   procedure Initiate_Close
     (Conn : in out Tcp_Connection;
      Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16)
   is
   begin
      Reply_Len := 0;
      if Conn.State = ESTABLISHED then
         Conn.State := FIN_WAIT_1;
         Build_Tcp_Reply (Conn, Flag_FIN or Flag_ACK,
           Conn.Our_Seq, Conn.Client_Seq, (0 .. -1 => 0), Reply_Buf, Reply_Len);
         --  FIN consumes one sequence number.
         Conn.Our_Seq := Conn.Our_Seq + 1;
      end if;
   end Initiate_Close;

   procedure Find_Connection (Table : in out Tcp_Conn_Table; IP : Unsigned_32; Port : Unsigned_16; Result : out Integer) is
   begin
      Expire_Stale (Table);
      Result := -1;
      for I in Table'Range loop
         if Table (I).State /= CLOSED
           and then Table (I).Client_IP = IP
           and then Table (I).Client_Port = Port
         then
            Result := I;
            return;
         end if;
      end loop;
   end Find_Connection;

   procedure Alloc_Connection (Table : in out Tcp_Conn_Table; Result : out Integer) is
   begin
      Expire_Stale (Table);
      Result := -1;
      for I in Table'Range loop
         if Table (I).State = CLOSED then
            Result := I;
            return;
         end if;
      end loop;
   end Alloc_Connection;

end Schild_Tcp_Handler;
