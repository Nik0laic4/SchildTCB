-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Schild TCB — SHA-256 compression core (FIPS 180-4, section 6.2.2).
-- Proved at SPARK Level 4 (no runtime error): the 64-round message schedule
-- and the round loop index constrained arrays. The padding / length handling
-- stays in Schild_HMAC_SHA256 (validated by RFC 4231 / NIST KAT).

with Interfaces; use Interfaces;

package Schild_Sha256_Compress
  with SPARK_Mode => On
is
   subtype U32 is Unsigned_32;

   type U32_Array_16 is array (0 .. 15) of U32;
   type U32_Array_8  is array (0 .. 7) of U32;

   --  One SHA-256 compression round (FIPS 180-4 §6.2.2): absorb one 16-word
   --  message block into the running state.
   procedure Compress_Block
     (Block : U32_Array_16;
      State : in out U32_Array_8);

end Schild_Sha256_Compress;
