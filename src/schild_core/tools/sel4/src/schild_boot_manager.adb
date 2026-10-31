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

   function Get_U8 (Block : Counter_Block; Off : Natural) return Unsigned_8 is
   begin
      return Block (Off);
   end Get_U8;

   function Get_U32 (Block : Counter_Block; Off : Natural) return Unsigned_32 is
   begin
      return Unsigned_32 (Block (Off + 0))
           or Shift_Left (Unsigned_32 (Block (Off + 1)), 8)
           or Shift_Left (Unsigned_32 (Block (Off + 2)), 16)
           or Shift_Left (Unsigned_32 (Block (Off + 3)), 24);
   end Get_U32;

   function Get_U64 (Block : Counter_Block; Off : Natural) return Unsigned_64 is
   begin
      return Unsigned_64 (Block (Off + 0))
           or Shift_Left (Unsigned_64 (Block (Off + 1)), 8)
           or Shift_Left (Unsigned_64 (Block (Off + 2)), 16)
           or Shift_Left (Unsigned_64 (Block (Off + 3)), 24)
           or Shift_Left (Unsigned_64 (Block (Off + 4)), 32)
           or Shift_Left (Unsigned_64 (Block (Off + 5)), 40)
           or Shift_Left (Unsigned_64 (Block (Off + 6)), 48)
           or Shift_Left (Unsigned_64 (Block (Off + 7)), 56);
   end Get_U64;

   procedure Put_U32 (Block : in out Counter_Block; Off : Natural; V : Unsigned_32) with
     Pre => Off <= 508
   is
   begin
      Block (Off + 0) := Unsigned_8 (V and 16#FF#);
      Block (Off + 1) := Unsigned_8 (Shift_Right (V, 8)  and 16#FF#);
      Block (Off + 2) := Unsigned_8 (Shift_Right (V, 16) and 16#FF#);
      Block (Off + 3) := Unsigned_8 (Shift_Right (V, 24) and 16#FF#);
   end Put_U32;

   procedure Put_U64 (Block : in out Counter_Block; Off : Natural; V : Unsigned_64) with
     Pre => Off <= 504
   is
   begin
      Block (Off + 0) := Unsigned_8 (V and 16#FF#);
      Block (Off + 1) := Unsigned_8 (Shift_Right (V, 8)  and 16#FF#);
      Block (Off + 2) := Unsigned_8 (Shift_Right (V, 16) and 16#FF#);
      Block (Off + 3) := Unsigned_8 (Shift_Right (V, 24) and 16#FF#);
      Block (Off + 4) := Unsigned_8 (Shift_Right (V, 32) and 16#FF#);
      Block (Off + 5) := Unsigned_8 (Shift_Right (V, 40) and 16#FF#);
      Block (Off + 6) := Unsigned_8 (Shift_Right (V, 48) and 16#FF#);
      Block (Off + 7) := Unsigned_8 (Shift_Right (V, 56) and 16#FF#);
   end Put_U64;

   function Compute_Tag (Image : Counter_Block) return SHA256_Hash is
   begin
      return SHA256 (Image (0 .. 479));
   end Compute_Tag;

   function Verify_Block (Block : Sealed_Block) return Boolean is
   begin
      if Block.Image (0) /= 16#53# or else Block.Image (1) /= 16#43#
        or else Block.Image (2) /= 16#48# or else Block.Image (3) /= 16#4C#
        or else Block.Image (4) /= 16#44# or else Block.Image (5) /= 16#42#
        or else Block.Image (6) /= 16#43# or else Block.Image (7) /= 16#31#
      then
         return False;
      end if;
      if Get_U32 (Block.Image, 8) /= 1 then
         return False;
      end if;
      return Block.Tag = Compute_Tag (Block.Image);
   end Verify_Block;

   function Encode_Block (State : Persistent_State) return Sealed_Block is
      B : Sealed_Block;
   begin
      B.Image := (others => 0);
      B.Image (0) := 16#53#; B.Image (1) := 16#43#;
      B.Image (2) := 16#48#; B.Image (3) := 16#4C#;
      B.Image (4) := 16#44#; B.Image (5) := 16#42#;
      B.Image (6) := 16#43#; B.Image (7) := 16#31#;
      Put_U32 (B.Image, 8, 1);
      Put_U64 (B.Image, 16, State.Boot_Count);
      Put_U64 (B.Image, 24, State.Failed_Boot_Count);
      B.Image (32) := (if State.Active_Slot = Slot_A then 0 else 1);
      Put_U32 (B.Image, 33, Unsigned_32 (State.Slot_A_Attempts));
      Put_U32 (B.Image, 37, Unsigned_32 (State.Slot_B_Attempts));
      B.Image (41) := 0;
      if State.Slot_A_Locked then
         B.Image (41) := B.Image (41) or Unsigned_8'(1);
      end if;
      if State.Slot_B_Locked then
         B.Image (41) := B.Image (41) or Unsigned_8'(2);
      end if;
      if State.Both_Locked then
         B.Image (41) := B.Image (41) or Unsigned_8'(4);
      end if;
      B.Tag := Compute_Tag (B.Image);
      return B;
   end Encode_Block;

   function Decode_Block (Block : Sealed_Block) return Persistent_State is
      S : Persistent_State;
   begin
      S.Boot_Count        := Get_U64 (Block.Image, 16);
      S.Failed_Boot_Count := Get_U64 (Block.Image, 24);
      S.Active_Slot       := (if Block.Image (32) = 0 then Slot_A else Slot_B);
      S.Slot_A_Attempts   := Unsigned_64 (Get_U32 (Block.Image, 33));
      S.Slot_B_Attempts   := Unsigned_64 (Get_U32 (Block.Image, 37));
      S.Slot_A_Locked     := (Block.Image (41) and 1) /= 0;
      S.Slot_B_Locked     := (Block.Image (41) and 2) /= 0;
      S.Both_Locked       := (Block.Image (41) and 4) /= 0;
      return S;
   end Decode_Block;

end Schild_Boot_Manager;
