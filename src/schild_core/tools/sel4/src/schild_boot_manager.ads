-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.1 — A/B Boot Manager (Junos dual-root-partition pattern)
--
-- Maintains two boot slots (A and B), each with a root_task image.
-- SHA-256 verification ensures boot integrity. If the active slot
-- fails verification, the system atomically switches to the backup.
--
-- Architecture:
--   Slot A: primary image   (verified at boot)
--   Slot B: fallback image  (used if A fails checksum)
--   Atomic switch: update boot slot flag → reboot → new image
-- =============================================================================

with Interfaces;          use Interfaces;
with Schild_HMAC_SHA256;   use Schild_HMAC_SHA256;

package Schild_Boot_Manager
  with SPARK_Mode => On
is
   -- Boot slot identifier
   type Boot_Slot is (Slot_A, Slot_B);

   -- SHA-256 hash (32 bytes = 4 x 64-bit words)
   subtype SHA256_Hash is Schild_HMAC_SHA256.SHA256_Hash;

   -- Boot manager state
   type Boot_Manager is record
      Active_Slot       : Boot_Slot;
      Slot_A_Hash       : SHA256_Hash;  -- expected hash for slot A
      Slot_B_Hash       : SHA256_Hash;  -- expected hash for slot B
      Verified          : Boolean;      -- current image verified OK
      Boot_Count        : Unsigned_64;  -- total boots since install
      Failed_Boot_Count : Unsigned_64;  -- boots that failed verification
   end record;

   -- Compute SHA-256 hash of a memory region
   -- (Stage 7.2: replace with real SHA-256; Stage 7.1: constant for testing)
   function Compute_Hash
     (Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return SHA256_Hash
   with
     Pre => Image_Size > 0;

   -- Verify boot image against expected hash
   function Verify_Image
     (Manager   : Boot_Manager;
      Slot      : Boot_Slot;
      Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return Boolean;

   -- Switch to the other slot (atomic failover)
   procedure Failover
     (Manager : in out Boot_Manager)
   with
     Post => Manager.Active_Slot /= Manager.Active_Slot'Old;

   -- Record a successful boot (increments boot counter)
   procedure Record_Successful_Boot
     (Manager : in out Boot_Manager)
   with
     Post => Manager.Boot_Count = Manager.Boot_Count'Old + 1;

   -- Initialize boot manager with default (safe) state
   procedure Initialize
     (Manager : out Boot_Manager)
   with
     Post => Manager.Active_Slot = Slot_A
             and not Manager.Verified;

end Schild_Boot_Manager;
