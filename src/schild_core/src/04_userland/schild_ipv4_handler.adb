-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- Schild TCB Stage 7.9: IPv4 Handler — body

package body Schild_Ipv4_Handler with SPARK_Mode => Off is

   ----------------
   -- Parse_Ipv4 --
   ----------------
   procedure Parse_Ipv4
     (Raw    : in  Byte_Array;
      Result : out Ipv4_Result;
      Valid  : out Boolean)
   is
      IHL : Unsigned_8;
      use type Unsigned_16; use type Unsigned_32;
   begin
      Valid := False;
      -- Fully initialize the OUT record so early returns (invalid IHL /
      -- length guards) leave no uninitialized field for the caller.
      Result := (Header      => (Version_IHL => 0, DSCP_ECN => 0, Total_Len => 0, Ident => 0,
                                 Flags_Frag => 0, TTL => 0, Protocol => 0, Checksum => 0,
                                 Src_IP => 0, Dst_IP => 0),
                 Is_For_Us   => False,
                 Checksum_OK => False,
                 Header_Len  => 20,
                 Payload_Off => 20,
                 Payload_Len => 0);
      Result.Header.Version_IHL := Raw (Raw'First);
      IHL := Result.Header.Version_IHL and 16#0F#;
      if IHL < 5 or IHL > 15 then return; end if;

      Result.Header.DSCP_ECN  := Raw (Raw'First + 1);
      Result.Header.Total_Len := Shift_Left (Unsigned_16 (Raw (Raw'First + 2)), 8)
                                 or Unsigned_16 (Raw (Raw'First + 3));
      Result.Header.Ident     := Shift_Left (Unsigned_16 (Raw (Raw'First + 4)), 8)
                                 or Unsigned_16 (Raw (Raw'First + 5));
      Result.Header.Flags_Frag:= Shift_Left (Unsigned_16 (Raw (Raw'First + 6)), 8)
                                 or Unsigned_16 (Raw (Raw'First + 7));
      Result.Header.TTL       := Raw (Raw'First + 8);
      Result.Header.Protocol  := Raw (Raw'First + 9);
      Result.Header.Checksum  := Shift_Left (Unsigned_16 (Raw (Raw'First + 10)), 8)
                                 or Unsigned_16 (Raw (Raw'First + 11));
      Result.Header.Src_IP    := Shift_Left (Unsigned_32 (Raw (Raw'First + 12)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 13)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 14)), 8)
        or Unsigned_32 (Raw (Raw'First + 15));
      Result.Header.Dst_IP    := Shift_Left (Unsigned_32 (Raw (Raw'First + 16)), 24)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 17)), 16)
        or Shift_Left (Unsigned_32 (Raw (Raw'First + 18)), 8)
        or Unsigned_32 (Raw (Raw'First + 19));

      Result.Header_Len  := Unsigned_16 (IHL) * 4;
      Result.Payload_Off := Result.Header_Len;
      if Result.Header.Total_Len < Result.Header_Len then return; end if;
      --  Upper-bound guard (remote-DoS defence): reject datagrams whose header
      --  claims more bytes than were actually received. Without this,
      --  Payload_Len can reach ~65515 and downstream allocates huge stack
      --  buffers / reads out of bounds, crashing the kernel.
      if Result.Header.Total_Len > Unsigned_16 (Raw'Length) then return; end if;
      Result.Payload_Len := Result.Header.Total_Len - Result.Header_Len;
      Result.Is_For_Us   := (Result.Header.Dst_IP = Our_IP);
      Result.Checksum_OK := (Compute_Ipv4_Checksum (Result.Header) = Result.Header.Checksum);
      Valid := True;
   end Parse_Ipv4;

   -----------------------------
   -- Compute_Ipv4_Checksum   --
   -----------------------------
   function Compute_Ipv4_Checksum (Header : Ipv4_Header) return Unsigned_16 is
      Sum : Unsigned_32 := 0;
      W   : Unsigned_16;
   begin
      W := Shift_Left (Unsigned_16 (Header.Version_IHL), 8)
           or Unsigned_16 (Header.DSCP_ECN);
      Sum := Sum + Unsigned_32 (W);
      Sum := Sum + Unsigned_32 (Header.Total_Len);
      Sum := Sum + Unsigned_32 (Header.Ident);
      Sum := Sum + Unsigned_32 (Header.Flags_Frag);
      W := Shift_Left (Unsigned_16 (Header.TTL), 8)
           or Unsigned_16 (Header.Protocol);
      Sum := Sum + Unsigned_32 (W);
      -- High/low 16-bit words of Src_IP / Dst_IP, expressed with modular
      -- arithmetic (provable) instead of bit masks (hard for SMT bit-vectors).
      Sum := Sum + (Header.Src_IP / 65536);
      Sum := Sum + (Header.Src_IP mod 65536);
      Sum := Sum + (Header.Dst_IP / 65536);
      Sum := Sum + (Header.Dst_IP mod 65536);
      -- RFC 1071 fold: (Sum and 0xFFFF) + (Sum >> 16)
      --                  == (Sum mod 65536) + (Sum / 65536).
      -- The accumulator is bounded by 9 * 65535, so two fold steps suffice.
      Sum := (Sum mod 65536) + (Sum / 65536);
      Sum := (Sum mod 65536) + (Sum / 65536);
      -- One's complement of the low 16 bits:
      --   (not Sum) and 0xFFFF == 65535 - (Sum mod 65536).
      return Unsigned_16 (65535 - (Sum mod 65536));
   end Compute_Ipv4_Checksum;

   -------------------------
   -- Build_Ipv4_Header   --
   -------------------------
   procedure Build_Ipv4_Header
     (Proto       : in  Unsigned_8;
      Dst_IP      : in  Unsigned_32;
      Payload_Len : in  Unsigned_16;
      Hdr_Buf     : out Byte_Array;
      Hdr_Len     : out Unsigned_16)
     with Pre => Payload_Len <= 65515,
          Post => Hdr_Len = 20,
          Relaxed_Initialization => Hdr_Buf
   is
      Hdr : Ipv4_Header;
      Idx : Integer := Hdr_Buf'First;
      procedure Put_U8 (V : Unsigned_8) is begin
         Hdr_Buf (Idx) := V; Idx := Idx + 1;
      end Put_U8;
      procedure Put_U16 (V : Unsigned_16) is begin
         Hdr_Buf (Idx) := Unsigned_8 (Shift_Right (V, 8) and 255);
         Hdr_Buf (Idx + 1) := Unsigned_8 (V and 255); Idx := Idx + 2;
      end Put_U16;
      procedure Put_U32 (V : Unsigned_32) is begin
         Put_U16 (Unsigned_16 (Shift_Right (V, 16) and 65535));
         Put_U16 (Unsigned_16 (V and 65535));
      end Put_U32;
      use type Unsigned_16;
   begin
      Hdr.Version_IHL := 16#45#;
      Hdr.DSCP_ECN    := 0;
      Hdr.Total_Len   := 20 + Payload_Len;
      Hdr.Ident       := 0;
      Hdr.Flags_Frag  := 16#4000#;
      Hdr.TTL         := 64;
      Hdr.Protocol    := Proto;
      Hdr.Checksum    := 0;
      Hdr.Src_IP      := Our_IP;
      Hdr.Dst_IP      := Dst_IP;
      Hdr.Checksum := Compute_Ipv4_Checksum (Hdr);

      Put_U8  (Hdr.Version_IHL);
      Put_U8  (Hdr.DSCP_ECN);
      Put_U16 (Hdr.Total_Len);
      Put_U16 (Hdr.Ident);
      Put_U16 (Hdr.Flags_Frag);
      Put_U8  (Hdr.TTL);
      Put_U8  (Hdr.Protocol);
      Put_U16 (Hdr.Checksum);
      Put_U32 (Hdr.Src_IP);
      Put_U32 (Hdr.Dst_IP);
      Hdr_Len := Unsigned_16 (Idx - Hdr_Buf'First);
   end Build_Ipv4_Header;

   ------------------------
   -- Build_Ipv4_Frame   --
   ------------------------
   procedure Build_Ipv4_Frame
     (Dst_MAC    : in  Unsigned_8_Array_6;
      Src_MAC    : in  Unsigned_8_Array_6;
      Proto      : in  Unsigned_8;
      Dst_IP     : in  Unsigned_32;
      Payload    : in  Byte_Array;
      Frame_Buf  : out Byte_Array;
      Frame_Len  : out Unsigned_16)
   is
      Idx : Integer := Frame_Buf'First;
      procedure Put_U8 (V : Unsigned_8) is begin
         Frame_Buf (Idx) := V; Idx := Idx + 1;
      end Put_U8;
      procedure Put_U16 (V : Unsigned_16) is begin
         Frame_Buf (Idx) := Unsigned_8 (Shift_Right (V, 8) and 255);
         Frame_Buf (Idx + 1) := Unsigned_8 (V and 255); Idx := Idx + 2;
      end Put_U16;
      Ipv4_Buf : Byte_Array (0 .. 19);
      Ipv4_Len : Unsigned_16;
   begin
      for J in 0 .. 5 loop Put_U8 (Dst_MAC (J)); end loop;
      for J in 0 .. 5 loop Put_U8 (Src_MAC (J)); end loop;
      Put_U16 (16#0800#);
      Build_Ipv4_Header (Proto, Dst_IP, Unsigned_16 (Payload'Length),
                         Ipv4_Buf, Ipv4_Len);
      for J in 0 .. Integer (Ipv4_Len) - 1 loop
         Put_U8 (Ipv4_Buf (Ipv4_Buf'First + J));
      end loop;
      for J in Payload'Range loop Put_U8 (Payload (J)); end loop;
      Frame_Len := Unsigned_16 (Idx - Frame_Buf'First);
   end Build_Ipv4_Frame;

end Schild_Ipv4_Handler;

