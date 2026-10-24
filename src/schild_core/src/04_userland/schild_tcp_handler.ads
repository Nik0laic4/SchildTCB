-- Schild TCB Stage 7.9: Minimal TCP Handler (RFC 793)

with Interfaces; with Schild_Net_Types; with Schild_Net_Config;

package Schild_Tcp_Handler with SPARK_Mode => Off is
   use Interfaces;

   subtype Byte_Array is Schild_Net_Types.Byte_Array;
   subtype Unsigned_8_Array_6 is Byte_Array (0 .. 5);

   HTTP_Port : constant Unsigned_16 := 80;
   Flag_FIN  : constant Unsigned_8 := 1;  Flag_SYN : constant Unsigned_8 := 2;
   Flag_RST  : constant Unsigned_8 := 4;  Flag_PSH : constant Unsigned_8 := 8;
   Flag_ACK  : constant Unsigned_8 := 16;

   type Tcp_Header is record
      Src_Port : Unsigned_16 := 0; Dst_Port : Unsigned_16 := 0;
      Seq_Num  : Unsigned_32 := 0; Ack_Num  : Unsigned_32 := 0;
      Data_Off : Unsigned_8 := 16#50#; Flags : Unsigned_8 := 0;
      Window   : Unsigned_16 := 1460; Checksum : Unsigned_16 := 0;
      Urgent_Ptr : Unsigned_16 := 0;
   end record;

   type Tcp_State is (CLOSED, LISTEN, SYN_RCVD, ESTABLISHED, CLOSE_WAIT, LAST_ACK,
                      FIN_WAIT_1, FIN_WAIT_2);

   type Tcp_Connection is record
      State : Tcp_State := CLOSED;
      Client_IP : Unsigned_32 := 0; Client_Port : Unsigned_16 := 0;
      Client_MAC : Unsigned_8_Array_6 := (others => 0);
      Our_Seq : Unsigned_32 := 0; Client_Seq : Unsigned_32 := 0;
      Last_Active : Unsigned_64 := 0;   -- RDTSC at last segment (idle timeout)
   end record;

   Max_Connections : constant := 8;
   type Tcp_Conn_Table is array (0 .. Max_Connections - 1) of Tcp_Connection;

   --  Pseudo-random initial sequence number (RDTSC + per-boot counter),
   --  replacing the previous fixed 16#DEAD_BEEF# (predictable-ISN flaw).
   function Generate_Isn return Unsigned_32;

   function Find_Connection (Table : in out Tcp_Conn_Table; IP : Unsigned_32; Port : Unsigned_16) return Integer;
   function Alloc_Connection (Table : in out Tcp_Conn_Table) return Integer;

   procedure Parse_Tcp (Raw : in Byte_Array; Header : out Tcp_Header; Valid : out Boolean)
     with Pre => Raw'Length >= 20;

   procedure Process_Tcp
     (Conn : in out Tcp_Connection; Tcp_Hdr : in Tcp_Header;
      Src_IP : in Unsigned_32; Src_MAC : in Unsigned_8_Array_6;
      Payload : in Byte_Array; Reply_Buf : out Byte_Array;
      Reply_Len : out Unsigned_16; Has_Data : out Boolean)
     with Pre => Reply_Buf'Length >= 1500;

   procedure Build_Tcp_Reply
     (Conn : in out Tcp_Connection; Flags : Unsigned_8;
      Seq, Ack : Unsigned_32; Payload : Byte_Array;
      Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16)
     with Pre => Reply_Buf'Length >= 1500;

   --  Server-initiated close: after serving a response the server sends FIN
   --  (HTTP/1.0 always answers "Connection: close"). Valid only from
   --  ESTABLISHED; transitions the connection to FIN_WAIT_1 and returns the
   --  FIN segment to transmit (Reply_Len = 0 if the state was not ESTABLISHED).
   procedure Initiate_Close
     (Conn : in out Tcp_Connection;
      Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16)
     with Pre => Reply_Buf'Length >= 1500;

   function Validate_Tcp_Checksum (Src_IP, Dst_IP : Unsigned_32;
      Tcp_Seg : Byte_Array) return Boolean
     with Pre => Tcp_Seg'Length >= 20;

   Our_IP : Unsigned_32 renames Schild_Net_Config.Our_IP;
end Schild_Tcp_Handler;
