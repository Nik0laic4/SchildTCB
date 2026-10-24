-- Schild TCB Stage 7.9: ARP Handler (RFC 826)

with Interfaces; with Schild_Net_Types; with Schild_Net_Config;

package Schild_Arp_Handler with SPARK_Mode => Off is
   use Interfaces;

   subtype Unsigned_8_Array is Schild_Net_Types.Byte_Array;

   ARP_Request : constant Unsigned_16 := 1;
   ARP_Reply   : constant Unsigned_16 := 2;
   HW_Ethernet : constant Unsigned_16 := 1;

   type Mac_Addr is array (0 .. 5) of Unsigned_8;

   type Arp_Entry is record
      IP : Unsigned_32 := 0; MAC : Mac_Addr := (others => 0); Valid : Boolean := False;
   end record;
   type Arp_Table is array (0 .. 7) of Arp_Entry;

   Our_IP : Unsigned_32 renames Schild_Net_Config.Our_IP;

   type Arp_Packet is record
      HW_Type : Unsigned_16 := 0; Proto_Type : Unsigned_16 := 0;
      HW_Len : Unsigned_8 := 6; Proto_Len : Unsigned_8 := 4;
      Operation : Unsigned_16 := 0;
      Sender_MAC : Mac_Addr := (others => 0); Sender_IP : Unsigned_32 := 0;
      Target_MAC : Mac_Addr := (others => 0); Target_IP : Unsigned_32 := 0;
   end record;

   procedure Parse_Arp (Raw : in Unsigned_8_Array; Arp : out Arp_Packet; Valid : out Boolean)
     with Pre => Raw'Length >= 28;

   procedure Build_Arp_Reply (Request_Arp : in Arp_Packet;
     Src_MAC : in Mac_Addr;
     Reply_Buf : out Unsigned_8_Array; Reply_Len : out Unsigned_16)
     with Pre => Reply_Buf'Length >= 42;

   procedure Cache_Lookup (Table : in Arp_Table; IP : in Unsigned_32;
     MAC : out Mac_Addr; Found : out Boolean);

   procedure Cache_Update (Table : in out Arp_Table; IP : in Unsigned_32; MAC : in Mac_Addr);

   Ether_Type_ARP  : constant Unsigned_16 := 16#0806#;
   Ether_Type_IPv4 : constant Unsigned_16 := 16#0800#;
end Schild_Arp_Handler;
