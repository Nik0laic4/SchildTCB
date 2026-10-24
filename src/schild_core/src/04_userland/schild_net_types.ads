-- Schild TCB Stage 7.9: Common network types — canonical Byte_Array for ALL modules

with Interfaces;

package Schild_Net_Types with SPARK_Mode => Off is
   use Interfaces;

   subtype Byte_Index is Integer range 0 .. 4095;
   type Byte_Array is array (Byte_Index range <>) of Unsigned_8;
   subtype Mac_Addr_6 is Byte_Array (0 .. 5);

   Our_MAC : constant Mac_Addr_6 := (16#52#, 16#54#, 16#00#, 16#12#, 16#34#, 16#56#);
   Our_IP  : constant Unsigned_32 := 16#C0A8_03C8#;
   Ether_Type_ARP  : constant Unsigned_16 := 16#0806#;
   Ether_Type_IPv4 : constant Unsigned_16 := 16#0800#;
end Schild_Net_Types;
