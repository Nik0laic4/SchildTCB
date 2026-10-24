package body Schild_User_Barrier with
  SPARK_Mode => On
is

   -----------------------------
   -- Capture_And_Freeze_Args --
   -----------------------------
   procedure Capture_And_Freeze_Args
     (Raw_Vector : in Positive;
      Raw_Param  : in Long_Integer;
      Snapshot   : out Safe_Args_Snapshot)
   is
   begin
      --  Freeze the raw arguments so later validation sees an immutable copy.
      Snapshot.Syscall_Vector := Raw_Vector;
      Snapshot.Param_Value    := Raw_Param;
      Snapshot.Is_Validated   := False;
   end Capture_And_Freeze_Args;

   ------------------------------
   -- Validate_Frozen_Snapshot --
   ------------------------------
   procedure Validate_Frozen_Snapshot
     (Snapshot   : in out Safe_Args_Snapshot;
      Max_Vector : in Positive;
      Is_Secure  : out Boolean)
   is
   begin
      Is_Secure := False;

      --  Accept only vectors within the allowed range.
      if Snapshot.Syscall_Vector <= Max_Vector then
         Snapshot.Is_Validated := True;
         Is_Secure             := True;
      end if;
   end Validate_Frozen_Snapshot;

end Schild_User_Barrier;
