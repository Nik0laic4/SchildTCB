--  Schild TCB - process manager (process table + MLS-aware lifecycle).
--  Tracks per-process capabilities, file descriptors, signals and MLS level, and
--  enforces Bell-LaPadula on creation, termination and signalling.

with Interfaces;
with Schild_Sel4_Ipc;
with Schild_File_Descriptors;
with Schild_Signals;

package Schild_Process_Manager with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   use Schild_Sel4_Ipc;
   use Schild_File_Descriptors;
   use Schild_Signals;
   use type Interfaces.Unsigned_32;

   --  Opaque process identifier (0 is the null PID).
   type Process_Id is mod 2**32;
   Null_PID : constant Process_Id := 0;

   --  Lifecycle states of a process.
   type Process_State is (Unborn, Ready, Running, Sleeping, Zombie, Dead);

   --  Four MLS clearance levels (1 = public, 4 = secret).
   subtype Mls_Level_Type is Interfaces.Unsigned_32 range 1 .. 4;
   Public_Level      : constant Mls_Level_Type := 1;
   Restricted_Level  : constant Mls_Level_Type := 2;
   Confidential_Level: constant Mls_Level_Type := 3;
   Secret_Level      : constant Mls_Level_Type := 4;

   --  Per-process state: capabilities, descriptors, signals and MLS level.
   type Process_Context is record
      Pid          : Process_Id := Null_PID;
      Parent_Pid   : Process_Id := Null_PID;
      Thread_Cap   : Cap_Id := Null_Cap;       -- seL4 TCB capability
      VSpace_Cap   : Cap_Id := Null_Cap;       -- Address space
      CNode_Cap    : Cap_Id := Null_Cap;       -- Capability space
      State        : Process_State := Unborn;
      Level        : Mls_Level_Type := Public_Level;
      Fds          : Descriptor_Table;
      Signals      : Signal_Context;
      Exit_Code    : Integer := 0;
   end record;

   --  Fixed-size process table.
   Max_Processes : constant := 64;
   type Process_Table is array (1 .. Max_Processes) of Process_Context;

   --  Result of a process-management operation.
   type Proc_Status is (Success, Table_Full, Invalid_PID, Access_Denied, Mls_Violation);

   ------------------------------------------------------------
   --  Process operations.
   ------------------------------------------------------------

   --  Reset the process table to a clean (all-Dead) state.
   procedure Init_Process_Table (Table : out Process_Table)
   with Post => (for all I in Table'Range =>
                   Table (I).State = Dead and Table (I).Pid = Null_PID);

   --  Create a process owned by Parent_Pid with the given capabilities.
   procedure Create_Process
     (Table       : in out Process_Table;
      Parent_Pid  : in     Process_Id;
      Thread_Cap  : in     Cap_Id;
      VSpace_Cap  : in     Cap_Id;
      CNode_Cap   : in     Cap_Id;
      Level       : in     Mls_Level_Type;
      New_Pid     :    out Process_Id;
      Status      :    out Proc_Status)
   with
     Post => (if Status = Success then
                New_Pid /= Null_PID
                  and (for some I in Table'Range =>
                         Table (I).Pid = New_Pid
                           and Table (I).Parent_Pid = Parent_Pid
                           and Table (I).Thread_Cap = Thread_Cap
                           and Table (I).VSpace_Cap = VSpace_Cap
                           and Table (I).CNode_Cap = CNode_Cap
                           and Table (I).State = Ready
                           and Table (I).Level = Level));

   --  Terminate a process; fails with Mls_Violation if the caller is below it.
   procedure Terminate_Process
     (Table        : in out Process_Table;
      Pid          : in     Process_Id;
      Caller_Level : in     Mls_Level_Type;
      Force        : in     Boolean;
      Status       :    out Proc_Status)
   with
     Pre  => Pid /= Null_PID,
     Post => (if Status = Mls_Violation then
                Table = Table'Old  -- no control-up: the target is untouched
              else
                Status = Success or Status = Invalid_PID);

   --  Wait for a child process to exit.
   procedure Wait_Process
     (Table   : in out Process_Table;
      Pid     : in     Process_Id;
      Status  :    out Proc_Status)
   with Post => (if Status = Success then
                   (for some I in Table'Range =>
                      Table'Old (I).Pid = Pid
                        and Table'Old (I).State = Zombie
                        and Table (I).State = Dead
                        and Table (I).Pid = Null_PID));

   --  Return the stored context of a process.
   function Get_Process_Context
     (Table : Process_Table;
      Pid   : Process_Id) return Process_Context;

   --  True when two processes are at the same MLS level.
   function Check_Mls_Compatibility
     (Proc1_Level : Mls_Level_Type;
      Proc2_Level : Mls_Level_Type) return Boolean
   with Post => Check_Mls_Compatibility'Result = (Proc1_Level = Proc2_Level);

   --  Deliver all pending signals in the table.
   procedure Deliver_Pending_Signals
     (Table : in out Process_Table);

   --  Reap exited (Zombie) processes.
   procedure Reap_Zombies
     (Table : in out Process_Table)
   with
     Post => Table = Table'Old;  -- no-op by design: reaping is the parent's Wait

private
   --  Slot index into Process_Table; 0 is the "not found" sentinel. Narrowing
   --  the return type (0 .. Max_Processes) makes every `Table (Slot)` indexing
   --  provably in-range after the `Slot = 0` guard.
   subtype Slot_Index is Integer range 0 .. Max_Processes;
   function Find_Free_Slot (Table : Process_Table) return Slot_Index
   with Post => (if Find_Free_Slot'Result = 0 then
                   (for all I in Table'Range => Table (I).State /= Dead)
                 else
                   Table (Find_Free_Slot'Result).State = Dead);
   function Find_Process (Table : Process_Table; Pid : Process_Id) return Slot_Index
   with Post => (if Find_Process'Result = 0 then
                   (for all I in Table'Range =>
                      not (Table (I).Pid = Pid and Table (I).State /= Dead))
                 else
                   Table (Find_Process'Result).Pid = Pid
                     and Table (Find_Process'Result).State /= Dead);
   function Has_Active_Process (Table : Process_Table) return Boolean
   with Post => Has_Active_Process'Result =
                (for some I in Table'Range => Table (I).State /= Dead);
end Schild_Process_Manager;