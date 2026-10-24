-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — HMAC-SHA256 body (RFC 2104 / FIPS 198-1, SHA-256 FIPS 180-4)
-- =============================================================================

package body Schild_HMAC_SHA256
  with SPARK_Mode => Off
is
   subtype U32 is Unsigned_32;
   subtype U64 is Unsigned_64;
   subtype U8  is Unsigned_8;

   type U32_Array_16 is array (0 .. 15) of U32;
   type U32_Array_8  is array (0 .. 7) of U32;
   subtype U8_Array_64 is Byte_Array (0 .. 63);
   subtype U8_Array_8  is Byte_Array (0 .. 7);
   subtype U8_Array_32 is Byte_Array (0 .. 31);

   --  Round constants (FIPS 180-4, section 4.2.2).
   K : constant array (0 .. 63) of U32 :=
     (16#428a2f98#, 16#71374491#, 16#b5c0fbcf#, 16#e9b5dba5#,
      16#3956c25b#, 16#59f111f1#, 16#923f82a4#, 16#ab1c5ed5#,
      16#d807aa98#, 16#12835b01#, 16#243185be#, 16#550c7dc3#,
      16#72be5d74#, 16#80deb1fe#, 16#9bdc06a7#, 16#c19bf174#,
      16#e49b69c1#, 16#efbe4786#, 16#0fc19dc6#, 16#240ca1cc#,
      16#2de92c6f#, 16#4a7484aa#, 16#5cb0a9dc#, 16#76f988da#,
      16#983e5152#, 16#a831c66d#, 16#b00327c8#, 16#bf597fc7#,
      16#c6e00bf3#, 16#d5a79147#, 16#06ca6351#, 16#14292967#,
      16#27b70a85#, 16#2e1b2138#, 16#4d2c6dfc#, 16#53380d13#,
      16#650a7354#, 16#766a0abb#, 16#81c2c92e#, 16#92722c85#,
      16#a2bfe8a1#, 16#a81a664b#, 16#c24b8b70#, 16#c76c51a3#,
      16#d192e819#, 16#d6990624#, 16#f40e3585#, 16#106aa070#,
      16#19a4c116#, 16#1e376c08#, 16#2748774c#, 16#34b0bcb5#,
      16#391c0cb3#, 16#4ed8aa4a#, 16#5b9cca4f#, 16#682e6ff3#,
      16#748f82ee#, 16#78a5636f#, 16#84c87814#, 16#8cc70208#,
      16#90befffa#, 16#a4506ceb#, 16#bef9a3f7#, 16#c67178f2#);

   --  Initial hash values (FIPS 180-4, section 5.3.3).
   Initial_H : constant U32_Array_8 :=
     (16#6a09e667#, 16#bb67ae85#, 16#3c6ef372#, 16#a54ff53a#,
      16#510e527f#, 16#9b05688c#, 16#1f83d9ab#, 16#5be0cd19#);

   --  Rotate right by N bits (modular, N in 0 .. 31).
   function ROR (X : U32; N : Natural) return U32 is
      NN : constant Natural := N mod 32;
   begin
      if NN = 0 then
         return X;
      end if;
      return Shift_Right (X, NN) or Shift_Left (X, 32 - NN);
   end ROR;

   --  SHA-256 compression function (FIPS 180-4, section 6.2.2).
   procedure Compress_Block (Block : U32_Array_16; State : in out U32_Array_8)
   is
      W : array (0 .. 63) of U32;
      A, B, C, D, E, F, G, H : U32;
      T1, T2 : U32;
   begin
      --  Message schedule: the first 16 words come from the block, the rest
      --  are derived from the recurrence W[i] = W[i-16] + s0(W[i-15])
      --  + W[i-7] + s1(W[i-2]).
      for I in 0 .. 15 loop
         W (I) := Block (I);
      end loop;
      for I in 16 .. 63 loop
         W (I) := W (I - 16) +
           (ROR (W (I - 15), 7) xor ROR (W (I - 15), 18)
              xor Shift_Right (W (I - 15), 3)) +
           W (I - 7) +
           (ROR (W (I - 2), 17) xor ROR (W (I - 2), 19)
              xor Shift_Right (W (I - 2), 10));
      end loop;

      A := State (0); B := State (1); C := State (2); D := State (3);
      E := State (4); F := State (5); G := State (6); H := State (7);

      for I in 0 .. 63 loop
         declare
            S1 : constant U32 := ROR (E, 6) xor ROR (E, 11) xor ROR (E, 25);
            Ch : constant U32 := (E and F) xor ((not E) and G);
            S0 : constant U32 := ROR (A, 2) xor ROR (A, 13) xor ROR (A, 22);
            Mj : constant U32 := (A and B) xor (A and C) xor (B and C);
         begin
            T1 := H + S1 + Ch + K (I) + W (I);
            T2 := S0 + Mj;
            H := G; G := F; F := E; E := D + T1;
            D := C; C := B; B := A; A := T1 + T2;
         end;
      end loop;

      State (0) := State (0) + A; State (1) := State (1) + B;
      State (2) := State (2) + C; State (3) := State (3) + D;
      State (4) := State (4) + E; State (5) := State (5) + F;
      State (6) := State (6) + G; State (7) := State (7) + H;
   end Compress_Block;

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
