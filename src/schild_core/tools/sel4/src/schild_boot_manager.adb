-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- INTERNAL STUB (TCB execution layer).
-- The proprietary A/B Boot Manager (SHA-256 verified failover) has been moved
-- out of this repository into private/. This body only satisfies the
-- public interface (Schild_Boot_Manager.ads) so the open build compiles.

package body Schild_Boot_Manager
  with SPARK_Mode => On
is
   function Compute_Hash
     (Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return SHA256_Hash
   is
      pragma Unreferenced (Image_Addr, Image_Size);
      Z : constant SHA256_Hash := (others => 0);
   begin
      return Z;
   end Compute_Hash;

   function Verify_Image
     (Manager    : Boot_Manager;
      Slot       : Boot_Slot;
      Image_Addr : Unsigned_64;
      Image_Size : Unsigned_64) return Boolean
   is
      pragma Unreferenced (Manager, Slot, Image_Addr, Image_Size);
   begin
      return False;
   end Verify_Image;

   function Slot_Locked
     (Manager : Boot_Manager;
      Slot    : Boot_Slot) return Boolean
   is
   begin
      return (if Slot = Slot_A then Manager.Slot_A_Locked
              else Manager.Slot_B_Locked);
   end Slot_Locked;

   function Is_Bricked (Manager : Boot_Manager) return Boolean is
   begin
      return Manager.Both_Locked;
   end Is_Bricked;

   function Health_Ok (Status : Health_Status) return Boolean is
   begin
      return Status.Network_Up and Status.MLS_Valid;
   end Health_Ok;

   procedure Failover
     (Manager : in out Boot_Manager)
   is
      Other : constant Boot_Slot :=
        (if Manager.Active_Slot = Slot_A then Slot_B else Slot_A);
   begin
      -- Decrement the failing slot's remaining attempts; lock it on exhaustion.
      -- (The precondition guarantees the active slot still has attempts left,
      -- so the subtraction cannot underflow.)
      if Manager.Active_Slot = Slot_A then
         Manager.Slot_A_Attempts := Manager.Slot_A_Attempts - 1;
         if Manager.Slot_A_Attempts = 0 then
            Manager.Slot_A_Locked := True;
         end if;
      else
         Manager.Slot_B_Attempts := Manager.Slot_B_Attempts - 1;
         if Manager.Slot_B_Attempts = 0 then
            Manager.Slot_B_Locked := True;
         end if;
      end if;

      Manager.Failed_Boot_Count := Manager.Failed_Boot_Count + 1;
      Manager.Verified := False;

      -- Switch to the backup slot only if it is still bootable.
      if Other = Slot_B then
         if not Manager.Slot_B_Locked then
            Manager.Active_Slot := Slot_B;
         end if;
      else
         if not Manager.Slot_A_Locked then
            Manager.Active_Slot := Slot_A;
         end if;
      end if;

      Manager.Both_Locked := Manager.Slot_A_Locked and Manager.Slot_B_Locked;
   end Failover;

   procedure Record_Successful_Boot
     (Manager : in out Boot_Manager)
   is
   begin
      Manager.Boot_Count := Manager.Boot_Count + 1;
      Manager.Verified := True;

      -- Commit the active slot: restore its full attempt budget and clear its
      -- lock flag (it just booted successfully).
      if Manager.Active_Slot = Slot_A then
         Manager.Slot_A_Attempts := Max_Boot_Attempts;
         Manager.Slot_A_Locked := False;
      else
         Manager.Slot_B_Attempts := Max_Boot_Attempts;
         Manager.Slot_B_Locked := False;
      end if;
   end Record_Successful_Boot;

   procedure Commit_If_Healthy
     (Manager : in out Boot_Manager;
      Status  : Health_Status)
   is
   begin
      if Health_Ok (Status) then
         Record_Successful_Boot (Manager);
      else
         Failover (Manager);
      end if;
   end Commit_If_Healthy;

   procedure Initialize
     (Manager : out Boot_Manager)
   is
   begin
      Manager.Active_Slot       := Slot_A;
      Manager.Slot_A_Hash       := (others => 0);
      Manager.Slot_B_Hash       := (others => 0);
      Manager.Verified          := False;
      Manager.Boot_Count        := 0;
      Manager.Failed_Boot_Count := 0;
      Manager.Slot_A_Attempts   := Max_Boot_Attempts;
      Manager.Slot_B_Attempts   := Max_Boot_Attempts;
      Manager.Slot_A_Locked     := False;
      Manager.Slot_B_Locked     := False;
      Manager.Both_Locked       := False;
   end Initialize;

   function To_Persistent (Manager : Boot_Manager) return Persistent_State is
   begin
      return (Boot_Count        => Manager.Boot_Count,
              Failed_Boot_Count => Manager.Failed_Boot_Count,
              Active_Slot       => Manager.Active_Slot,
              Slot_A_Attempts   => Manager.Slot_A_Attempts,
              Slot_B_Attempts   => Manager.Slot_B_Attempts,
              Slot_A_Locked     => Manager.Slot_A_Locked,
              Slot_B_Locked     => Manager.Slot_B_Locked,
              Both_Locked       => Manager.Both_Locked);
   end To_Persistent;

   function From_Persistent (State : Persistent_State) return Boot_Manager is
      M : Boot_Manager;
   begin
      M.Boot_Count        := State.Boot_Count;
      M.Failed_Boot_Count := State.Failed_Boot_Count;
      M.Active_Slot       := State.Active_Slot;
      M.Slot_A_Attempts   := State.Slot_A_Attempts;
      M.Slot_B_Attempts   := State.Slot_B_Attempts;
      M.Slot_A_Locked     := State.Slot_A_Locked;
      M.Slot_B_Locked     := State.Slot_B_Locked;
      M.Both_Locked       := State.Both_Locked;
      M.Verified          := False;
      M.Slot_A_Hash       := (others => 0);
      M.Slot_B_Hash       := (others => 0);
      return M;
   end From_Persistent;

end Schild_Boot_Manager;
