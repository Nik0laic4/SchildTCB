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

   -- Lockout threshold: a slot is LOCKED after this many consecutive failed
   -- boot attempts. Kept small so a persistently corrupt slot is abandoned
   -- quickly (bounded reboot loop), but > 1 to tolerate transient faults.
   Max_Boot_Attempts : constant Unsigned_64 := 3;

   -- Boot manager state
   type Boot_Manager is record
      Active_Slot       : Boot_Slot;
      Slot_A_Hash       : SHA256_Hash;  -- expected hash for slot A
      Slot_B_Hash       : SHA256_Hash;  -- expected hash for slot B
      Verified          : Boolean;      -- current image verified OK
      Boot_Count        : Unsigned_64;  -- successful boots recorded (committed)
      Failed_Boot_Count : Unsigned_64;  -- boots that failed verification
      Slot_A_Attempts   : Unsigned_64;  -- remaining attempts before lockout (A)
      Slot_B_Attempts   : Unsigned_64;  -- remaining attempts before lockout (B)
      Slot_A_Locked     : Boolean;      -- slot A exhausted its attempts
      Slot_B_Locked     : Boolean;      -- slot B exhausted its attempts
      Both_Locked       : Boolean;      -- bricked: no bootable slot remains
   end record;

   -- System health inputs for the health-gated commit (W9.2). Obtained from
   -- hardware/daemons before the active slot is committed:
   --   Network_Up — NIC link is up and the driver is ready;
   --   MLS_Valid  — the MLS policy daemon validated its configuration.
   type Health_Status is record
      Network_Up : Boolean;
      MLS_Valid  : Boolean;
   end record;

   -- The active slot is committed only when the system is healthy (network up
   -- AND MLS valid). This is the W9.2 gate between a successful boot and the
   -- commit of the slot.
   function Health_Ok (Status : Health_Status) return Boolean
   with
     Post => Health_Ok'Result = (Status.Network_Up and Status.MLS_Valid);

   -- Non-volatile projection of the boot manager (W9 Load/Save shim, logic).
   -- RAM-level counterpart of the NVMe counter block in BOOT_COUNTER_DESIGN.md
   -- §4; byte-level packing is deferred to the NVMe shim (hardware). The
   -- round-trip From_Persistent (To_Persistent M) preserves every field below.
   type Persistent_State is record
      Boot_Count        : Unsigned_64;
      Failed_Boot_Count : Unsigned_64;
      Active_Slot       : Boot_Slot;
      Slot_A_Attempts   : Unsigned_64;
      Slot_B_Attempts   : Unsigned_64;
      Slot_A_Locked     : Boolean;
      Slot_B_Locked     : Boolean;
      Both_Locked       : Boolean;
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

   -- True when the given slot is locked (its attempts are exhausted)
   function Slot_Locked
     (Manager : Boot_Manager;
      Slot    : Boot_Slot) return Boolean
   with
     Post => Slot_Locked'Result =
               (if Slot = Slot_A then Manager.Slot_A_Locked
                else Manager.Slot_B_Locked);

   -- True when both slots are locked and no bootable image remains
   function Is_Bricked (Manager : Boot_Manager) return Boolean
   with
     Post => Is_Bricked'Result = Manager.Both_Locked;

   -- Switch to the other slot after the active slot failed a boot attempt.
   -- The failing slot's remaining attempts are decremented; when they reach
   -- zero the slot is locked. The active slot is only switched to an unlocked
   -- slot; if no unlocked slot remains the manager is bricked.
   procedure Failover
     (Manager : in out Boot_Manager)
   with
     Pre  => not Manager.Both_Locked
             and Manager.Slot_A_Locked = (Manager.Slot_A_Attempts = 0)
             and Manager.Slot_B_Locked = (Manager.Slot_B_Attempts = 0)
             and (if Manager.Active_Slot = Slot_A then
                     not Manager.Slot_A_Locked
                  else
                     not Manager.Slot_B_Locked),
     Post =>
       Manager.Failed_Boot_Count = Manager.Failed_Boot_Count'Old + 1
       and not Manager.Verified
       and Manager.Boot_Count = Manager.Boot_Count'Old
       and Manager.Slot_A_Hash = Manager.Slot_A_Hash'Old
       and Manager.Slot_B_Hash = Manager.Slot_B_Hash'Old
       and Manager.Slot_A_Locked = (Manager.Slot_A_Attempts = 0)
       and Manager.Slot_B_Locked = (Manager.Slot_B_Attempts = 0)
       and Manager.Both_Locked = (Manager.Slot_A_Locked
                                  and Manager.Slot_B_Locked)
       and (if not Manager.Both_Locked then
               (if Manager.Active_Slot = Slot_A then
                   not Manager.Slot_A_Locked
                else
                   not Manager.Slot_B_Locked))
       and (if Manager.Active_Slot'Old = Slot_A then
               Manager.Slot_A_Attempts = Manager.Slot_A_Attempts'Old - 1
               and Manager.Slot_B_Attempts = Manager.Slot_B_Attempts'Old
               and Manager.Slot_B_Locked = Manager.Slot_B_Locked'Old
            else
               Manager.Slot_B_Attempts = Manager.Slot_B_Attempts'Old - 1
               and Manager.Slot_A_Attempts = Manager.Slot_A_Attempts'Old
               and Manager.Slot_A_Locked = Manager.Slot_A_Locked'Old)
       and Manager.Active_Slot =
             (if Manager.Active_Slot'Old = Slot_A then
                 (if Manager.Slot_B_Locked then Slot_A else Slot_B)
              else
                 (if Manager.Slot_A_Locked then Slot_B else Slot_A));

   -- Record a successful boot: increment the boot counter and commit the
   -- active slot by restoring its full attempt budget.
   procedure Record_Successful_Boot
     (Manager : in out Boot_Manager)
   with
     Pre  => not Manager.Both_Locked
             and Manager.Slot_A_Locked = (Manager.Slot_A_Attempts = 0)
             and Manager.Slot_B_Locked = (Manager.Slot_B_Attempts = 0)
             and (if Manager.Active_Slot = Slot_A then
                     not Manager.Slot_A_Locked
                  else
                     not Manager.Slot_B_Locked),
     Post =>
       Manager.Boot_Count = Manager.Boot_Count'Old + 1
       and Manager.Verified
       and Manager.Failed_Boot_Count = Manager.Failed_Boot_Count'Old
       and Manager.Both_Locked = Manager.Both_Locked'Old
       and Manager.Slot_A_Hash = Manager.Slot_A_Hash'Old
       and Manager.Slot_B_Hash = Manager.Slot_B_Hash'Old
       and Manager.Active_Slot = Manager.Active_Slot'Old
       and (if Manager.Active_Slot'Old = Slot_A then
               Manager.Slot_A_Attempts = Max_Boot_Attempts
               and not Manager.Slot_A_Locked
               and Manager.Slot_B_Attempts = Manager.Slot_B_Attempts'Old
               and Manager.Slot_B_Locked = Manager.Slot_B_Locked'Old
            else
               Manager.Slot_B_Attempts = Max_Boot_Attempts
               and not Manager.Slot_B_Locked
               and Manager.Slot_A_Attempts = Manager.Slot_A_Attempts'Old
               and Manager.Slot_A_Locked = Manager.Slot_A_Locked'Old);

   -- Health-gated commit (W9.2): commit the active slot only when the system
   -- is healthy; otherwise fail over to the backup slot.
   procedure Commit_If_Healthy
     (Manager : in out Boot_Manager;
      Status  : Health_Status)
   with
     Pre  => not Manager.Both_Locked
             and Manager.Slot_A_Locked = (Manager.Slot_A_Attempts = 0)
             and Manager.Slot_B_Locked = (Manager.Slot_B_Attempts = 0)
             and (if Manager.Active_Slot = Slot_A then
                     not Manager.Slot_A_Locked
                  else
                     not Manager.Slot_B_Locked),
     Post =>
       (if Health_Ok (Status) then
           Manager.Boot_Count = Manager.Boot_Count'Old + 1
           and Manager.Verified
        else
           Manager.Failed_Boot_Count = Manager.Failed_Boot_Count'Old + 1
           and not Manager.Verified);

   -- Initialize boot manager with default (safe) state: slot A active, full
   -- attempt budget on both slots, nothing locked.
   procedure Initialize
     (Manager : out Boot_Manager)
   with
     Post => Manager.Active_Slot = Slot_A
             and not Manager.Verified
             and Manager.Boot_Count = 0
             and Manager.Failed_Boot_Count = 0
             and Manager.Slot_A_Attempts = Max_Boot_Attempts
             and Manager.Slot_B_Attempts = Max_Boot_Attempts
             and not Manager.Slot_A_Locked
             and not Manager.Slot_B_Locked
             and not Manager.Both_Locked;

   -- Project the persisted counter state out of the boot manager.
   function To_Persistent (Manager : Boot_Manager) return Persistent_State
   with
     Post => To_Persistent'Result.Boot_Count = Manager.Boot_Count
             and To_Persistent'Result.Failed_Boot_Count = Manager.Failed_Boot_Count
             and To_Persistent'Result.Active_Slot = Manager.Active_Slot
             and To_Persistent'Result.Slot_A_Attempts = Manager.Slot_A_Attempts
             and To_Persistent'Result.Slot_B_Attempts = Manager.Slot_B_Attempts
             and To_Persistent'Result.Slot_A_Locked = Manager.Slot_A_Locked
             and To_Persistent'Result.Slot_B_Locked = Manager.Slot_B_Locked
             and To_Persistent'Result.Both_Locked = Manager.Both_Locked;

   -- Rebuild a boot manager from persisted state (hashes/Verified reset).
   function From_Persistent (State : Persistent_State) return Boot_Manager
   with
     Post => From_Persistent'Result.Boot_Count = State.Boot_Count
             and From_Persistent'Result.Failed_Boot_Count = State.Failed_Boot_Count
             and From_Persistent'Result.Active_Slot = State.Active_Slot
             and From_Persistent'Result.Slot_A_Attempts = State.Slot_A_Attempts
             and From_Persistent'Result.Slot_B_Attempts = State.Slot_B_Attempts
             and From_Persistent'Result.Slot_A_Locked = State.Slot_A_Locked
             and From_Persistent'Result.Slot_B_Locked = State.Slot_B_Locked
             and From_Persistent'Result.Both_Locked = State.Both_Locked
             and not From_Persistent'Result.Verified;

end Schild_Boot_Manager;
