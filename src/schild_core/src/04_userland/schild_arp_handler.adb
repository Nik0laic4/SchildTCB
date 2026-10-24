-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- Schild TCB Stage 7.9: ARP Handler — body

package body Schild_Arp_Handler with SPARK_Mode => Off is

   ---------------
   -- Parse_Arp --
   ---------------
   procedure Parse_Arp
     (Raw  : in  Unsigned_8_Array;
      Arp  : out Arp_Packet;
      Valid: out Boolean)
   is
      use type Unsigned_16;
   begin
      Valid := False;
      -- HW_Type bytes 0-1
      Arp.HW_Type := Shift_Left (Unsigned_16 (Raw (Raw'First)), 8)
                     or Unsigned_16 (Raw (Raw'First + 1));
      -- Proto_Type bytes 2-3
      Arp.Proto_Type := Shift_Left (Unsigned_16 (Raw (Raw'First + 2)), 8)
                        or Unsigned_16 (Raw (Raw'First + 3));
      -- HW_Len byte 4
      Arp.HW_Len := Raw (Raw'First + 4);
      -- Proto_Len byte 5
      Arp.Proto_Len := Raw (Raw'First + 5);
      -- Operation bytes 6-7
      Arp.Operation := Shift_Left (Unsigned_16 (Raw (Raw'First + 6)), 8)
                       or Unsigned_16 (Raw (Raw'First + 7));
      -- Sender MAC bytes 8-13
      for I in 0 .. 5 loop
         Arp.Sender_MAC (I) := Raw (Raw'First + 8 + I);
      end loop;
      -- Sender IP bytes 14-17
      Arp.Sender_IP := Shift_Left (Unsigned_32 (Raw (Raw'First + 14)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 15)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 16)), 8)
        or Unsigned_32 (Raw (Raw'First + 17));
      -- Target MAC bytes 18-23
      for I in 0 .. 5 loop
         Arp.Target_MAC (I) := Raw (Raw'First + 18 + I);
      end loop;
      -- Target IP bytes 24-27
      Arp.Target_IP := Shift_Left (Unsigned_32 (Raw (Raw'First + 24)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 25)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 26)), 8)
        or Unsigned_32 (Raw (Raw'First + 27));

      if Arp.HW_Type = HW_Ethernet and then Arp.Proto_Type = Ether_Type_IPv4
        and then Arp.HW_Len = 6 and then Arp.Proto_Len = 4
      then
         Valid := True;
      end if;
   end Parse_Arp;

   ----------------------
   -- Build_Arp_Reply --
   ----------------------
   procedure Build_Arp_Reply
     (Request_Arp : in  Arp_Packet;
      Src_MAC     : in  Mac_Addr;
      Reply_Buf   : out Unsigned_8_Array;
      Reply_Len   : out Unsigned_16)
   is
      Idx : Integer := Reply_Buf'First;
      procedure Put_U8 (V : Unsigned_8) is begin
         Reply_Buf (Idx) := V; Idx := Idx + 1;
      end Put_U8;
      procedure Put_U16 (V : Unsigned_16) is begin
         Reply_Buf (Idx) := Unsigned_8 (Shift_Right (V, 8) and 255);
         Reply_Buf (Idx + 1) := Unsigned_8 (V and 255);
         Idx := Idx + 2;
      end Put_U16;
      procedure Put_U32 (V : Unsigned_32) is begin
         Put_U16 (Unsigned_16 (Shift_Right (V, 16) and 65535));
         Put_U16 (Unsigned_16 (V and 65535));
      end Put_U32;
   begin
      -- Ethernet header: reply to sender
      for J in 0 .. 5 loop Put_U8 (Request_Arp.Sender_MAC (J)); end loop; -- Dst
      for J in 0 .. 5 loop Put_U8 (Src_MAC (J)); end loop;                -- Src
      Put_U16 (Ether_Type_ARP);

      -- ARP reply
      Put_U16 (HW_Ethernet);
      Put_U16 (Ether_Type_IPv4);
      Put_U8  (6);   -- HW_Len
      Put_U8  (4);   -- Proto_Len
      Put_U16 (ARP_Reply);
      for J in 0 .. 5 loop Put_U8 (Src_MAC (J)); end loop;                -- Sender MAC
      Put_U32 (Our_IP);                                                   -- Sender IP
      for J in 0 .. 5 loop Put_U8 (Request_Arp.Sender_MAC (J)); end loop;-- Target MAC
      Put_U32 (Request_Arp.Sender_IP);                                    -- Target IP

      Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
   end Build_Arp_Reply;

   -------------------
   -- Cache_Lookup --
   -------------------
   procedure Cache_Lookup
     (Table : in  Arp_Table;
      IP    : in  Unsigned_32;
      MAC   : out Mac_Addr;
      Found : out Boolean) is
   begin
      Found := False;
      MAC   := (others => 0);
      for I in Table'Range loop
         if Table (I).Valid and then Table (I).IP = IP then
            MAC   := Table (I).MAC;
            Found := True;
            return;
         end if;
      end loop;
   end Cache_Lookup;

   -------------------
   -- Cache_Update --
   -------------------
   procedure Cache_Update
     (Table : in out Arp_Table;
      IP    : in     Unsigned_32;
      MAC   : in     Mac_Addr) is
   begin
      -- Overwrite existing entry if found
      for I in Table'Range loop
         if Table (I).Valid and then Table (I).IP = IP then
            Table (I).MAC := MAC; return;
         end if;
      end loop;
      -- Insert into first free slot
      for I in Table'Range loop
         if not Table (I).Valid then
            Table (I) := (IP => IP, MAC => MAC, Valid => True);
            return;
         end if;
      end loop;
   end Cache_Update;

end Schild_Arp_Handler;
