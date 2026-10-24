-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — HMAC-SHA256 (RFC 2104 / FIPS 198-1, SHA-256 per FIPS 180-4)
--
-- Pure Ada, allocation-free implementation for Boot Manager image verification.
-- SPARK-compatible: no access types, bounded loops, no dynamic memory.
--
-- The spec is proved (SPARK_Mode => On); the compression body is intentionally
-- SPARK_Mode => Off (the 64-round message schedule is outside the Level-4 gate)
-- but is validated against the RFC 4231 and NIST known-answer vectors by
-- tools/sel4/tests/hmac_kat.adb (run via run_hmac_kat.sh).
-- =============================================================================

with Interfaces; use Interfaces;

package Schild_HMAC_SHA256
  with SPARK_Mode => On
is
   --  SHA-256 digest: 32 bytes packed big-endian into four 64-bit words.
   --    Element 0 = h0 (bits 63..32) || h1 (bits 31..0)
   --    Element 1 = h2 || h3
   --    Element 2 = h4 || h5
   --    Element 3 = h6 || h7
   --  where h0..h7 are the eight 32-bit SHA-256 state words (FIPS 180-4).
   type SHA256_Hash is array (0 .. 3) of Unsigned_64;

   --  General byte-string type for keys and messages.
   type Byte_Array is array (Natural range <>) of Unsigned_8;

   --  64-byte HMAC key block. Used only by the legacy Compute_HMAC entry point;
   --  callers supply an already zero-padded block (keys of at most 64 bytes).
   --  Keys longer than 64 bytes must go through HMAC_SHA256, which hashes the
   --  key first (RFC 2104, step 1).
   type HMAC_Key is array (0 .. 63) of Unsigned_8;

   --  SHA-256 of an arbitrary-length message (FIPS 180-4).
   function SHA256 (Data : Byte_Array) return SHA256_Hash;

   --  HMAC-SHA256 (RFC 2104 / FIPS 198-1) of arbitrary-length key and message.
   function HMAC_SHA256
     (Key  : Byte_Array;
      Data : Byte_Array) return SHA256_Hash;

   --  Legacy entry point retained for the A/B Boot Manager: HMAC-SHA256 over
   --  the Msg_Bytes most-significant bytes of Message (big-endian), using a
   --  pre-padded 64-byte key block.
   function Compute_HMAC
     (Key       : HMAC_Key;
      Message   : Unsigned_64;
      Msg_Bytes : Natural) return SHA256_Hash
   with
     Pre => Msg_Bytes in 1 .. 8;

   --  Legacy entry point: SHA-256 of the eight bytes of Data (big-endian).
   function SHA256_Block (Data : Unsigned_64) return SHA256_Hash;

end Schild_HMAC_SHA256;
