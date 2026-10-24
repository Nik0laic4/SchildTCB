-- Schild TCB Stage 7.9: Network Stack Dispatcher
-- All Byte_Array types are subtypes of Schild_Net_Types.Byte_Array — compatible!

with System; with Interfaces; with Schild_Net_Types;
with Schild_Uart_Driver; with Schild_E1000e;
with Schild_Arp_Handler; with Schild_Ipv4_Handler;
with Schild_Tcp_Handler; with Schild_Http_Server;
with Schild_Nvme;

package body Schild_Net_Stack with SPARK_Mode => Off is
   use Interfaces;
   subtype B is Schild_Net_Types.Byte_Array;
   subtype E is Schild_E1000e.Unsigned_8_Array;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   -- IRQ-driven RX: the e1000e IRQ handler (vector 0x30) sets this flag on a
   -- RX interrupt; Run_Loop halts on it instead of busy-polling.  (Only the
   -- standalone kernel calls Run_Loop; the seL4 NetServer drives RX via its
   -- own seL4 IRQ notification + Poll_And_Process.)
   C_Rx_Pending : Unsigned_32;
   pragma Import (C, C_Rx_Pending, "e1000e_rx_pending");
   pragma Volatile (C_Rx_Pending);
   procedure C_Hlt;       pragma Import (C, C_Hlt,       "schild_hlt");
   procedure C_Sti;       pragma Import (C, C_Sti,       "schild_sti");
   procedure C_Cli;       pragma Import (C, C_Cli,       "schild_cli");
   -- Diagnostic: handler invocation count + TSC + hex logging.
   C_Irq_Count : Unsigned_32;
   pragma Import (C, C_Irq_Count, "e1000e_irq_count");
   pragma Volatile (C_Irq_Count);
   procedure C_Log_Hex32 (V : Unsigned_32);
   pragma Import (C, C_Log_Hex32, "schild_log_hex32");

   Arp_Table : Schild_Arp_Handler.Arp_Table :=
     (others => (IP => 0, MAC => (others => 0), Valid => False));
   Tcp_Table : Schild_Tcp_Handler.Tcp_Conn_Table;

   Msg_Rx_Arp : constant String := "[NET] RX ARP";
   Msg_Rx_Ipv : constant String := "[NET] RX IPv4";
   Msg_Rx_Irq : constant String := "[IRQ] e1000e RX";

   procedure Flush_Log_To_Nvme is
   begin
      Schild_Nvme.Flush_Log_To_Nvme;
   end Flush_Log_To_Nvme;

   procedure B_to_E (Src : B; Dst : out E; Len : Integer) is
   begin for J in 0 .. Len - 1 loop Dst (J) := Src (Src'First + J); end loop; end B_to_E;

   procedure Handle_Arp  (Rx_Buf : E; Rx_Len : Unsigned_16);
   procedure Handle_Ipv4 (Rx_Buf : E; Rx_Len : Unsigned_16);
   procedure Handle_Icmp (Rx_Buf : E; Ipv4_Res : Schild_Ipv4_Handler.Ipv4_Result; Ipv4_Raw : B);
   procedure Handle_Tcp  (Rx_Buf : E; Ipv4_Res : Schild_Ipv4_Handler.Ipv4_Result; Ipv4_Raw : B);

   procedure Init is
      Msg : constant String := "[NET] Stack ready. Listening on :80";
   begin
      -- NVMe is already initialized by the kernel entry; re-initializing here
      -- would re-reset the SM981 controller and hang on real hardware.
      -- Connection table defaults to CLOSED; inbound SYNs allocate a slot on demand.
      C_Putln (Msg'Address, Msg'Length);
      Flush_Log_To_Nvme;
   end Init;

   function Poll_And_Process return Boolean is
      Rx_Buf  : E (0 .. 2047);
      Rx_Len  : Unsigned_16;
   begin
      if not Schild_E1000e.Poll_Rx (Rx_Buf, Rx_Len) then
         return False;
      end if;
      if Rx_Len >= 14 then
         declare
            Eth_Type : constant Unsigned_16 :=
              Shift_Left (Unsigned_16 (Rx_Buf (12)), 8) or Unsigned_16 (Rx_Buf (13));
         begin
            if Eth_Type = Schild_Net_Types.Ether_Type_ARP then
               C_Putln (Msg_Rx_Arp'Address, Msg_Rx_Arp'Length);
               Handle_Arp (Rx_Buf, Rx_Len);
            elsif Eth_Type = Schild_Net_Types.Ether_Type_IPv4 then
               C_Putln (Msg_Rx_Ipv'Address, Msg_Rx_Ipv'Length);
               Handle_Ipv4 (Rx_Buf, Rx_Len);
            end if;
         end;
      end if;
      return True;
   end Poll_And_Process;

   procedure Run_Loop is
      Pkt_Count : Unsigned_32 := 0;
      Msg_Cnt   : constant String := "[IRQ] irq_count=0x";
   begin
      loop
         -- IRQ-driven idle: halt until the RX interrupt fires. The cli/sti
         -- dance around the flag check closes the missed-wakeup race: while
         -- interrupts are disabled the flag check is safe, and sti+hlt is
         -- atomic on x86, so a flag set by the handler between the check and
         -- hlt still wakes the CPU on the pending interrupt.
         C_Cli;
         while C_Rx_Pending = 0 loop
            C_Sti;
            C_Hlt;
            C_Cli;
         end loop;
         C_Sti;
         C_Rx_Pending := 0;
         C_Putln (Msg_Rx_Irq'Address, Msg_Rx_Irq'Length);
         C_Putln (Msg_Cnt'Address, Msg_Cnt'Length);
         C_Log_Hex32 (C_Irq_Count);
         -- Drain the RX ring: one interrupt can signal up to NUM_DESC frames.
         for K in 1 .. 8 loop
            exit when not Poll_And_Process;
            Pkt_Count := Pkt_Count + 1;
            if (Pkt_Count and 7) = 0 then
               Flush_Log_To_Nvme;  -- NVMe write ~ms: flush every 8 packets
            end if;
         end loop;
      end loop;
   end Run_Loop;

   procedure Handle_Arp (Rx_Buf : E; Rx_Len : Unsigned_16) is
      Plen : constant Integer := Integer (Rx_Len) - 14;
      Arp_Raw : B (0 .. Plen - 1);
      Arp_Pkt : Schild_Arp_Handler.Arp_Packet;
      Arp_OK  : Boolean;
      Reply_Buf : B (0 .. 41);
      Reply_Len : Unsigned_16;
      Tx_Buf    : E (0 .. 41);
   begin
      for J in Arp_Raw'Range loop Arp_Raw (J) := Rx_Buf (14 + J); end loop;
      Schild_Arp_Handler.Parse_Arp (Arp_Raw, Arp_Pkt, Arp_OK);
      if Arp_OK and then Arp_Pkt.Operation = Schild_Arp_Handler.ARP_Request
        and then Arp_Pkt.Target_IP = Schild_Arp_Handler.Our_IP then
         declare
            Drv_MAC : constant Schild_E1000e.Mac_Addr := Schild_E1000e.Get_MAC;
            Our_MAC : Schild_Arp_Handler.Mac_Addr;
         begin
            for J in 0 .. 5 loop Our_MAC (J) := Drv_MAC (J); end loop;
            Schild_Arp_Handler.Build_Arp_Reply (Arp_Pkt, Our_MAC, Reply_Buf, Reply_Len);
         end;
         B_to_E (Reply_Buf, Tx_Buf, Integer (Reply_Len));
         Schild_E1000e.Send_Packet (Tx_Buf, Reply_Len);
      end if;
   end Handle_Arp;

   procedure Handle_Ipv4 (Rx_Buf : E; Rx_Len : Unsigned_16) is
      Plen : constant Integer := Integer (Rx_Len) - 14;
      Ipv4_Raw : B (0 .. Plen - 1);
      Ipv4_Res : Schild_Ipv4_Handler.Ipv4_Result;
      Ipv4_OK  : Boolean;
   begin
      for J in Ipv4_Raw'Range loop Ipv4_Raw (J) := Rx_Buf (14 + J); end loop;
      Schild_Ipv4_Handler.Parse_Ipv4 (Ipv4_Raw, Ipv4_Res, Ipv4_OK);
      if not Ipv4_OK or not Ipv4_Res.Is_For_Us or not Ipv4_Res.Checksum_OK then
         return;
      end if;
      if Ipv4_Res.Header.Protocol = Schild_Ipv4_Handler.Proto_ICMP then
         Handle_Icmp (Rx_Buf, Ipv4_Res, Ipv4_Raw);
      elsif Ipv4_Res.Header.Protocol = Schild_Ipv4_Handler.Proto_TCP then
         Handle_Tcp (Rx_Buf, Ipv4_Res, Ipv4_Raw);
      end if;
   end Handle_Ipv4;

   procedure Handle_Icmp (Rx_Buf : E; Ipv4_Res : Schild_Ipv4_Handler.Ipv4_Result;
                          Ipv4_Raw : B) is
      POff : constant Integer := Integer (Ipv4_Res.Payload_Off);
      PLen : constant Integer := Integer (Ipv4_Res.Payload_Len);
   begin
      if Ipv4_Raw (POff) /= 8 then return; end if;
      declare
         Icmp_Reply : B (0 .. PLen + 33);
         Icmp_Len   : Unsigned_16;
         Dst_MAC, Src_MAC : Schild_Ipv4_Handler.Unsigned_8_Array_6;
         Tx_Buf : E (0 .. PLen + 33);
      begin
         -- Reply: Dst = sender's MAC (Rx_Buf 6..11), Src = our MAC (Rx_Buf 0..5).
         for J in 0 .. 5 loop Dst_MAC (J) := Rx_Buf (6 + J); Src_MAC (J) := Rx_Buf (J); end loop;
         for J in 0 .. PLen - 1 loop Icmp_Reply (34 + J) := Ipv4_Raw (POff + J); end loop;
         Icmp_Reply (34) := 0; Icmp_Reply (36) := 0; Icmp_Reply (37) := 0;
         Schild_Ipv4_Handler.Build_Ipv4_Frame (Dst_MAC, Src_MAC,
           Schild_Ipv4_Handler.Proto_ICMP, Ipv4_Res.Header.Src_IP,
           Icmp_Reply (34 .. 34 + PLen - 1), Icmp_Reply, Icmp_Len);
         B_to_E (Icmp_Reply, Tx_Buf, Integer (Icmp_Len));
         Schild_E1000e.Send_Packet (Tx_Buf, Icmp_Len);
      end;
   end Handle_Icmp;

   procedure Handle_Tcp (Rx_Buf : E; Ipv4_Res : Schild_Ipv4_Handler.Ipv4_Result;
                         Ipv4_Raw : B) is
      POff : constant Integer := Integer (Ipv4_Res.Payload_Off);
      PLen : constant Integer := Integer (Ipv4_Res.Payload_Len);
      Dst_MAC, Src_MAC : Schild_Ipv4_Handler.Unsigned_8_Array_6;
      Tcp_Raw : B (0 .. PLen - 1);
      Tcp_Hdr : Schild_Tcp_Handler.Tcp_Header;
      Tcp_OK  : Boolean;
      Reply_Buf : B (0 .. 1499);
      Reply_Len : Unsigned_16;
      Has_Data  : Boolean;
      Frame_Buf : B (0 .. 1500);
      Frame_Len : Unsigned_16;
      Tx_Buf    : E (0 .. 1500);
      Data_Off  : Integer;
      Conn_Idx  : Integer;
   begin
      for J in Tcp_Raw'Range loop Tcp_Raw (J) := Ipv4_Raw (POff + J); end loop;
      -- Reply: Dst = sender's MAC (Rx_Buf 6..11), Src = our MAC (Rx_Buf 0..5).
      for J in 0 .. 5 loop Dst_MAC (J) := Rx_Buf (6 + J); Src_MAC (J) := Rx_Buf (J); end loop;
      Schild_Tcp_Handler.Parse_Tcp (Tcp_Raw, Tcp_Hdr, Tcp_OK);
      if not Tcp_OK then return; end if;
      Data_Off := (Integer (Tcp_Hdr.Data_Off) / 16) * 4;
      if Data_Off < 20 then Data_Off := 20; end if;
      --  Upper-bound guard: reject segments whose header offset exceeds the
      --  received payload, so the payload slice can never run off the buffer.
      if Data_Off > Tcp_Raw'Length then return; end if;
      -- Validate the TCP checksum (pseudo-header + header + payload) before
      -- touching connection state, so corrupted segments are dropped.
      if not Schild_Tcp_Handler.Validate_Tcp_Checksum
        (Ipv4_Res.Header.Src_IP, Ipv4_Res.Header.Dst_IP, Tcp_Raw)
      then
         declare
            M : constant String := "[TCP] checksum FAIL";
         begin
            C_Putln (M'Address, M'Length);
         end;
         return;
      end if;
      -- Demultiplex by (source IP, source port); allocate a fresh slot for a
      -- new SYN so multiple concurrent clients are served independently.
      Conn_Idx := Schild_Tcp_Handler.Find_Connection
        (Tcp_Table, Ipv4_Res.Header.Src_IP, Tcp_Hdr.Src_Port);
      if Conn_Idx < 0 and then (Tcp_Hdr.Flags and Schild_Tcp_Handler.Flag_SYN) /= 0 then
         Conn_Idx := Schild_Tcp_Handler.Alloc_Connection (Tcp_Table);
      end if;
      if Conn_Idx < 0 then
         declare
            M : constant String := "[TCP] no connection";
         begin
            C_Putln (M'Address, M'Length);
         end;
         return;
      end if;
      Schild_Tcp_Handler.Process_Tcp (Tcp_Table (Conn_Idx), Tcp_Hdr, Ipv4_Res.Header.Src_IP,
        Dst_MAC, Tcp_Raw (Data_Off .. Tcp_Raw'Last),
        Reply_Buf, Reply_Len, Has_Data);
      if Reply_Len > 0 then
         Schild_Ipv4_Handler.Build_Ipv4_Frame (Dst_MAC, Src_MAC,
           Schild_Ipv4_Handler.Proto_TCP, Ipv4_Res.Header.Src_IP,
           Reply_Buf (0 .. Integer (Reply_Len) - 1), Frame_Buf, Frame_Len);
         B_to_E (Frame_Buf, Tx_Buf, Integer (Frame_Len));
         Schild_E1000e.Send_Packet (Tx_Buf, Frame_Len);
      end if;
      if Has_Data then
         declare
            Http_Payload : B (0 .. Tcp_Raw'Last - Data_Off);
            Http_Reply   : B (0 .. 4095);
            Http_Len, Tcp_DLen : Unsigned_16;
            Http_OK : Boolean;
            Tcp_Out, Http_Frame : B (0 .. 1500);
            Http_FLen : Unsigned_16;
            Http_Tx   : E (0 .. 1500);
         begin
            for J in Http_Payload'Range loop
               Http_Payload (J) := Tcp_Raw (Data_Off + J); end loop;
            Schild_Http_Server.Handle_Request (Http_Payload, Http_Reply, Http_Len, Http_OK);
            declare
               M : constant String := "[HTTP] req handled";
            begin
               C_Putln (M'Address, M'Length);
            end;
            if Http_OK then
               Schild_Tcp_Handler.Build_Tcp_Reply (Tcp_Table (Conn_Idx),
                 Schild_Tcp_Handler.Flag_PSH or Schild_Tcp_Handler.Flag_ACK,
                 Tcp_Table (Conn_Idx).Our_Seq, Tcp_Table (Conn_Idx).Client_Seq,
                 Http_Reply (0 .. Integer (Http_Len) - 1), Tcp_Out, Tcp_DLen);
               Schild_Ipv4_Handler.Build_Ipv4_Frame (Dst_MAC, Src_MAC,
                 Schild_Ipv4_Handler.Proto_TCP, Ipv4_Res.Header.Src_IP,
                 Tcp_Out (0 .. Integer (Tcp_DLen) - 1), Http_Frame, Http_FLen);
               B_to_E (Http_Frame, Http_Tx, Integer (Http_FLen));
               Schild_E1000e.Send_Packet (Http_Tx, Http_FLen);
               declare
                  M : constant String := "[HTTP] reply sent";
               begin
                  C_Putln (M'Address, M'Length);
               end;
               -- Advance our sequence past the response body we just sent so
               -- the next response carries a fresh Seq_Num.
               Tcp_Table (Conn_Idx).Our_Seq := Tcp_Table (Conn_Idx).Our_Seq + Unsigned_32 (Http_Len);

               --  HTTP/1.0 always answers "Connection: close": send FIN so the
               --  peer (a mobile browser) sees the connection closed and
               --  renders instead of spinning forever.
               Schild_Tcp_Handler.Initiate_Close (Tcp_Table (Conn_Idx), Tcp_Out, Tcp_DLen);
               if Tcp_DLen > 0 then
                  Schild_Ipv4_Handler.Build_Ipv4_Frame (Dst_MAC, Src_MAC,
                    Schild_Ipv4_Handler.Proto_TCP, Ipv4_Res.Header.Src_IP,
                    Tcp_Out (0 .. Integer (Tcp_DLen) - 1), Http_Frame, Http_FLen);
                  B_to_E (Http_Frame, Http_Tx, Integer (Http_FLen));
                  Schild_E1000e.Send_Packet (Http_Tx, Http_FLen);
                  declare
                     M : constant String := "[TCP] FIN sent";
                  begin
                     C_Putln (M'Address, M'Length);
                  end;
               end if;
            else
               declare
                  M : constant String := "[HTTP] req FAILED";
               begin
                  C_Putln (M'Address, M'Length);
               end;
            end if;
         end;
      end if;
   end Handle_Tcp;

end Schild_Net_Stack;
