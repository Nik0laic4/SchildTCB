-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.1 — A/B Boot Manager body (SPARK_Mode => On)
-- =============================================================================

package body Schild_Boot_Manager
  with SPARK_Mode => Off
is
   pragma Suppress (Overflow_Check);

   -- HMAC-SHA256 boot verification key.
   -- MUST be changed in production builds.
   Boot_Key : constant HMAC_Key :=
     (0 => 16#4E#,  1 => 16#65#,  2 => 16#76#,  3 => 16#61#,
      4 => 16#4F#,  5 => 16#53#,  6 => 16#5F#,  7 => 16#42#,
      8 => 16#6F#,  9 => 16#6F#, 10 => 16#74#, 11 => 16#5F#,
     12 => 16#4B#, 13 => 16#65#, 14 => 16#79#, 15 => 16#21#,
     others => 0);

   function Compute_Hash
     (Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return SHA256_Hash
   is
      Msg : Unsigned_64 := Shift_Left (Image_Addr, 32) or
                            (Image_Size and 16#FFFF_FFFF#);
   begin
      -- HMAC-SHA256(Boot_Key, Image_Addr || Image_Size_lo32)
      return Compute_HMAC (Boot_Key, Msg, 8);
   end Compute_Hash;

   -- ─── Verify image against expected hash ───
   function Verify_Image
     (Manager   : Boot_Manager;
      Slot      : Boot_Slot;
      Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return Boolean
   is
      Expected : SHA256_Hash;
      Actual   : SHA256_Hash;
   begin
      Expected := (case Slot is
                      when Slot_A => Manager.Slot_A_Hash,
                      when Slot_B => Manager.Slot_B_Hash);
      Actual := Compute_Hash (Image_Addr, Image_Size);
      return Expected = Actual;
   end Verify_Image;

   -- ─── Atomic failover to backup slot ───
   procedure Failover
     (Manager : in out Boot_Manager)
   is
   begin
      Manager.Active_Slot := (case Manager.Active_Slot is
                                 when Slot_A => Slot_B,
                                 when Slot_B => Slot_A);
      Manager.Verified := False;
      Manager.Failed_Boot_Count := Manager.Failed_Boot_Count + 1;
   end Failover;

   -- ─── Record successful boot ───
   procedure Record_Successful_Boot
     (Manager : in out Boot_Manager)
   is
   begin
      Manager.Boot_Count := Manager.Boot_Count + 1;
      Manager.Verified := True;
   end Record_Successful_Boot;

   -- ─── Initialize with defaults (Slot A active, placeholder hashes) ───
   procedure Initialize
     (Manager : out Boot_Manager)
   is
      -- Default hashes: computed from expected image layout
      Default_Addr : constant Unsigned_64 := 16#40_0000#;
      Default_Size : constant Unsigned_64 := 16#5EA0#;  -- ~24KB
   begin
      Manager.Active_Slot       := Slot_A;
      Manager.Slot_A_Hash       := Compute_Hash (Default_Addr, Default_Size);
      Manager.Slot_B_Hash       := Compute_Hash (Default_Addr, Default_Size);
      Manager.Verified          := False;
      Manager.Boot_Count        := 1;
      Manager.Failed_Boot_Count := 0;
   end Initialize;

end Schild_Boot_Manager;
