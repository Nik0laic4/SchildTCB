-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

pragma Spark_Mode (On);

package body Schild_Sha256_Compress is

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
      W : array (0 .. 63) of U32 := (others => 0);
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

end Schild_Sha256_Compress;
