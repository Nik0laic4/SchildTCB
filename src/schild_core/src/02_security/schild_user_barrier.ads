package Schild_User_Barrier with
  SPARK_Mode => On
is

   --  A frozen copy of the raw syscall arguments, validated separately.
   type Safe_Args_Snapshot is record
      Syscall_Vector : Positive;
      Param_Value    : Long_Integer;
      Is_Validated   : Boolean;
   end record;

   --  Copy raw arguments into a snapshot (before validation).
   procedure Capture_And_Freeze_Args
     (Raw_Vector : in Positive;
      Raw_Param  : in Long_Integer;
      Snapshot   : out Safe_Args_Snapshot)
   with
     Post => Snapshot.Syscall_Vector = Raw_Vector 
             and Snapshot.Param_Value = Raw_Param 
             and not Snapshot.Is_Validated;

   --  Validate the snapshot against the allowed vector range.
   procedure Validate_Frozen_Snapshot
     (Snapshot   : in out Safe_Args_Snapshot;
      Max_Vector : in Positive;
      Is_Secure  : out Boolean)
   with
     Post => (if Is_Secure then Snapshot.Is_Validated 
              and Snapshot.Syscall_Vector <= Max_Vector);

end Schild_User_Barrier;
