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

   procedure Failover
     (Manager : in out Boot_Manager)
   is
   begin
      if Manager.Active_Slot = Slot_A then
         Manager.Active_Slot := Slot_B;
      else
         Manager.Active_Slot := Slot_A;
      end if;
      Manager.Verified := False;
   end Failover;

   procedure Record_Successful_Boot
     (Manager : in out Boot_Manager)
   is
   begin
      Manager.Boot_Count := Manager.Boot_Count + 1;
      Manager.Verified := True;
   end Record_Successful_Boot;

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
   end Initialize;

end Schild_Boot_Manager;
