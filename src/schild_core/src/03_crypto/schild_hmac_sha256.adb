-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — HMAC-SHA256 body (RFC 2104 / FIPS 198-1, SHA-256 FIPS 180-4)
-- =============================================================================

with Schild_Sha256_Compress; use Schild_Sha256_Compress;

package body Schild_HMAC_SHA256
  with SPARK_Mode => Off
is
   subtype U64 is Unsigned_64;
   subtype U8  is Unsigned_8;

   subtype U8_Array_64 is Byte_Array (0 .. 63);
   subtype U8_Array_8  is Byte_Array (0 .. 7);
   subtype U8_Array_32 is Byte_Array (0 .. 31);

   --  Initial hash values (FIPS 180-4, section 5.3.3).
   Initial_H : constant U32_Array_8 :=
     (16#6a09e667#, 16#bb67ae85#, 16#3c6ef372#, 16#a54ff53a#,
      16#510e527f#, 16#9b05688c#, 16#1f83d9ab#, 16#5be0cd19#);

   --  Feed one 64-byte block (big-endian words) into the compression function.
   procedure Compress_Bytes (Msg : U8_Array_64; State : in out U32_Array_8)
   is
      Block : U32_Array_16;
   begin
      for I in 0 .. 15 loop
         Block (I) := U32 (Msg (4 * I))     * 16#1000000# +
                      U32 (Msg (4 * I + 1)) * 16#10000#   +
                      U32 (Msg (4 * I + 2)) * 16#100#     +
                      U32 (Msg (4 * I + 3));
      end loop;
      Compress_Block (Block, State);
   end Compress_Bytes;

   --  Pack the eight 32-bit state words into the four-word digest.
   function Pack (State : U32_Array_8) return SHA256_Hash is
   begin
      return (0 => U64 (State (0)) * 16#100000000# + U64 (State (1)),
              1 => U64 (State (2)) * 16#100000000# + U64 (State (3)),
              2 => U64 (State (4)) * 16#100000000# + U64 (State (5)),
              3 => U64 (State (6)) * 16#100000000# + U64 (State (7)));
   end Pack;

   --  Process the tail of a message, apply padding and the 64-bit big-endian
   --  bit length, then finalize. `State` must already reflect every byte that
   --  precedes `Data`; `Bit_Len` is the TOTAL message length in bits.
   function SHA256_Core
     (State   : U32_Array_8;
      Data    : Byte_Array;
      Bit_Len : U64) return SHA256_Hash
   is
      S    : U32_Array_8 := State;
      Full : constant Natural := Data'Length / 64;
      Tail : constant Natural := Data'Length mod 64;
   begin
      --  Whole 64-byte blocks.
      for B in 1 .. Full loop
         declare
            Blk : U8_Array_64;
         begin
            for I in 1 .. 64 loop
               Blk (I - 1) := Data (Data'First + (B - 1) * 64 + (I - 1));
            end loop;
            Compress_Bytes (Blk, S);
         end;
      end loop;

      --  Padding: append 0x80, zero-fill, then the 64-bit bit length. If the
      --  remaining bytes would occupy positions 56..63 of a block, a second
      --  block is required (FIPS 180-4, section 5.1.1).
      if Tail <= 55 then
         declare
            Blk : U8_Array_64 := (others => 0);
         begin
            for I in 1 .. Tail loop
               Blk (I - 1) := Data (Data'First + Full * 64 + (I - 1));
            end loop;
            Blk (Tail) := 16#80#;
            for I in 0 .. 7 loop
               Blk (56 + I) :=
                 U8 (Shift_Right (Bit_Len, (7 - I) * 8) and 16#FF#);
            end loop;
            Compress_Bytes (Blk, S);
         end;
      else
         declare
            Blk : U8_Array_64 := (others => 0);
         begin
            for I in 1 .. Tail loop
               Blk (I - 1) := Data (Data'First + Full * 64 + (I - 1));
            end loop;
            Blk (Tail) := 16#80#;
            Compress_Bytes (Blk, S);
         end;
         declare
            Blk : U8_Array_64 := (others => 0);
         begin
            for I in 0 .. 7 loop
               Blk (56 + I) :=
                 U8 (Shift_Right (Bit_Len, (7 - I) * 8) and 16#FF#);
            end loop;
            Compress_Bytes (Blk, S);
         end;
      end if;

      return Pack (S);
   end SHA256_Core;

   --  SHA-256 of an arbitrary-length message.
   function SHA256 (Data : Byte_Array) return SHA256_Hash is
   begin
      return SHA256_Core (Initial_H, Data, U64 (Data'Length) * 8);
   end SHA256;

   --  HMAC inner/outer processing over an already-normalized key block.
   function HMAC_Core (Key_Block : U8_Array_64; Data : Byte_Array)
      return SHA256_Hash
   is
      Ipad : U8_Array_64;
      Opad : U8_Array_64;
      Inner : SHA256_Hash;
      Inner_Bytes : U8_Array_32;
      St : U32_Array_8;
   begin
      for I in 0 .. 63 loop
         Ipad (I) := Key_Block (I) xor 16#36#;
         Opad (I) := Key_Block (I) xor 16#5C#;
      end loop;

      --  Inner = SHA256(Ipad || Data).
      St := Initial_H;
      Compress_Bytes (Ipad, St);
      Inner := SHA256_Core (St, Data, U64 (64 + Data'Length) * 8);

      --  Outer = SHA256(Opad || Inner).
      for I in 0 .. 3 loop
         declare
            W : constant U64 := Inner (I);
         begin
            for J in 0 .. 7 loop
               Inner_Bytes (I * 8 + J) :=
                 U8 (Shift_Right (W, (7 - J) * 8) and 16#FF#);
            end loop;
         end;
      end loop;

      St := Initial_H;
      Compress_Bytes (Opad, St);
      return SHA256_Core (St, Inner_Bytes, U64 (96 * 8));
   end HMAC_Core;

   --  HMAC-SHA256 (RFC 2104): normalize the key (hash if longer than the block
   --  size, else zero-pad) and run the inner/outer hash.
   function HMAC_SHA256 (Key : Byte_Array; Data : Byte_Array)
      return SHA256_Hash
   is
      Kpad : U8_Array_64 := (others => 0);
   begin
      if Key'Length > 64 then
         declare
            KH : constant SHA256_Hash := SHA256 (Key);
         begin
            for I in 0 .. 3 loop
               declare
                  W : constant U64 := KH (I);
               begin
                  for J in 0 .. 7 loop
                     Kpad (I * 8 + J) :=
                       U8 (Shift_Right (W, (7 - J) * 8) and 16#FF#);
                  end loop;
               end;
            end loop;
         end;
      else
         for I in 1 .. Key'Length loop
            Kpad (I - 1) := Key (Key'First + I - 1);
         end loop;
      end if;

      return HMAC_Core (Kpad, Data);
   end HMAC_SHA256;

   --  Legacy: HMAC-SHA256 of an 8-byte message with a pre-padded key block.
   function Compute_HMAC
     (Key       : HMAC_Key;
      Message   : Unsigned_64;
      Msg_Bytes : Natural) return SHA256_Hash
   is
      Kpad : U8_Array_64;
      Msg  : U8_Array_8 := (others => 0);
   begin
      for I in 0 .. 63 loop
         Kpad (I) := Key (I);
      end loop;
      for I in 1 .. Msg_Bytes loop
         Msg (I - 1) :=
           U8 (Shift_Right (Message, (Msg_Bytes - I) * 8) and 16#FF#);
      end loop;
      return HMAC_Core (Kpad, Msg);
   end Compute_HMAC;

   --  Legacy: SHA-256 of the eight bytes of Data (big-endian).
   function SHA256_Block (Data : Unsigned_64) return SHA256_Hash is
      Msg : U8_Array_8 := (others => 0);
   begin
      for I in 0 .. 7 loop
         Msg (I) := U8 (Shift_Right (Data, (7 - I) * 8) and 16#FF#);
      end loop;
      return SHA256 (Msg);
   end SHA256_Block;

end Schild_HMAC_SHA256;
