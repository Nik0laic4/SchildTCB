-- Schild TCB Stage 7.9: IPv4 Handler (RFC 791)

with Interfaces; with Schild_Net_Types; with Schild_Net_Config;

package Schild_Ipv4_Handler with SPARK_Mode => Off is
   use Interfaces;

   subtype Byte_Array is Schild_Net_Types.Byte_Array;
   subtype Unsigned_8_Array_6 is Byte_Array (0 .. 5);

   Proto_ICMP : constant Unsigned_8 := 1;
   Proto_TCP  : constant Unsigned_8 := 6;
   Proto_UDP  : constant Unsigned_8 := 17;

   type Ipv4_Header is record
      Version_IHL : Unsigned_8 := 16#45#; DSCP_ECN : Unsigned_8 := 0;
      Total_Len : Unsigned_16 := 0; Ident : Unsigned_16 := 0;
      Flags_Frag : Unsigned_16 := 0; TTL : Unsigned_8 := 64;
      Protocol : Unsigned_8 := 0; Checksum : Unsigned_16 := 0;
      Src_IP : Unsigned_32 := 0; Dst_IP : Unsigned_32 := 0;
   end record;

   type Ipv4_Result is record
      Header : Ipv4_Header; Is_For_Us : Boolean := False;
      Checksum_OK : Boolean := False;
      Header_Len : Unsigned_16 := 20; Payload_Off : Unsigned_16 := 20;
      Payload_Len : Unsigned_16 := 0;
   end record;

   Our_IP : Unsigned_32 renames Schild_Net_Config.Our_IP;

   procedure Parse_Ipv4 (Raw : in Byte_Array; Result : out Ipv4_Result; Valid : out Boolean)
     with Pre => Raw'Length >= 20;

   function Compute_Ipv4_Checksum (Header : Ipv4_Header) return Unsigned_16;

   procedure Build_Ipv4_Frame (Dst_MAC : in Unsigned_8_Array_6; Src_MAC : in Unsigned_8_Array_6;
     Proto : in Unsigned_8; Dst_IP : in Unsigned_32;
     Payload : in Byte_Array; Frame_Buf : out Byte_Array; Frame_Len : out Unsigned_16)
     with Pre => Frame_Buf'Length >= Payload'Length + 34;
end Schild_Ipv4_Handler;
