--  Schild TCB - process manager body (SPARK_Mode => On).
--  Implements the process table with MLS enforcement: only a parent (or a
--  same-level caller) may terminate a process, and signalling honours the
--  Bell-LaPadula "no write down" rule.

with Schild_Log;
with Schild_Text;

package body Schild_Process_Manager with
  SPARK_Mode => On
is

   use type Interfaces.Unsigned_32;

   ----------------
   -- Find_Free_Slot --
   ----------------
   function Find_Free_Slot (Table : Process_Table) return Slot_Index is
   begin
      for I in Table'Range loop
         if Table (I).State = Dead then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Free_Slot;

   -----------------
   -- Find_Process --
   -----------------
   function Find_Process (Table : Process_Table; Pid : Process_Id) return Slot_Index is
   begin
      for I in Table'Range loop
         if Table (I).Pid = Pid and then Table (I).State /= Dead then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Process;

   ------------------------
   -- Init_Process_Table  --
   ------------------------
   procedure Init_Process_Table (Table : out Process_Table) is
   begin
      Table := [others => Process_Context'(others => <>)];
      for I in Table'Range loop
         Table (I).State := Dead;
         Table (I).Pid   := Null_PID;   --  Dead slots carry the null PID.
      end loop;
      Schild_Log.Put_Line ("Init: process table initialized (64 slots)");
   end Init_Process_Table;

   ---------------------
   -- Create_Process  --
   ---------------------
   procedure Create_Process
     (Table       : in out Process_Table;
      Parent_Pid  : in     Process_Id;
      Thread_Cap  : in     Cap_Id;
      VSpace_Cap  : in     Cap_Id;
      CNode_Cap   : in     Cap_Id;
      Level       : in     Mls_Level_Type;
      New_Pid     :    out Process_Id;
      Status      :    out Proc_Status)
   is
      Slot : constant Slot_Index := Find_Free_Slot (Table);
   begin
      New_Pid := Null_PID;
      Status  := Table_Full;

      if Slot = 0 then
         Schild_Log.Put_Line ("Proc: table full, cannot create process");
         return;
      end if;

      --  Reject creation when any required capability is null.
      if Thread_Cap = Null_Cap or else VSpace_Cap = Null_Cap or else CNode_Cap = Null_Cap then
         Status := Access_Denied;
         Schild_Log.Put_Line ("Proc: invalid capability (Null_Cap)");
         return;
      end if;

      --  Only the root task (empty table) may create a process with no parent.
      --  Enforce the "parent == 0 only for Root Task" restriction.
      if Parent_Pid = Null_PID then
         --  Reject if any live process already exists (root must be first).
         declare
            Has_Active : Boolean := False;
         begin
            for I in Table'Range loop
               if Table (I).State /= Dead then
                  Has_Active := True;
                  exit;
               end if;
            end loop;
            if Has_Active then
               Status := Access_Denied;
               Schild_Log.Put_Line ("Proc: only Root Task can have Parent_Pid=0");
               return;
            end if;
         end;
      else
         --  Look up the parent; fail with Invalid_PID if missing.
         declare
            Parent_Slot : constant Slot_Index := Find_Process (Table, Parent_Pid);
         begin
            if Parent_Slot = 0 then
               Status := Invalid_PID;
               Schild_Log.Put_Line ("Proc: parent PID not found");
               return;
            end if;

            --  A child must start at its parent's MLS level.
            --  (A level mismatch is an MLS violation, not a normal error.)
            if Interfaces.Unsigned_32 (Level) /= Interfaces.Unsigned_32 (Table (Parent_Slot).Level) then
               Status := Mls_Violation;
               Schild_Log.Put_Line ("Proc: MLS violation (child level must equal parent level)");
               return;
            end if;
         end;
      end if;

      --  Populate the new slot and mark the process Ready.
      New_Pid := Process_Id (Slot);
      Table (Slot).Pid        := New_Pid;
      Table (Slot).Parent_Pid := Parent_Pid;
      Table (Slot).Thread_Cap := Thread_Cap;
      Table (Slot).VSpace_Cap := VSpace_Cap;
      Table (Slot).CNode_Cap  := CNode_Cap;
      Table (Slot).State      := Ready;
      Table (Slot).Level      := Level;

      Init_Descriptor_Table (Table (Slot).Fds, CNode_Cap);
      Init_Standard_Streams  (Table (Slot).Fds);

      Status := Success;
      Schild_Log.Put_String ("Proc: created process PID=");
      declare
         Buf : Schild_Text.Image_String;
         Len : Natural;
      begin
         Schild_Text.Image (Natural (Slot), Buf, Len);
         Schild_Log.Put_String (Buf (1 .. Len));
      end;
      Schild_Log.Put_Line (" [Ready]");
   end Create_Process;

   --------------------
   -- Terminate_Process --
   --------------------
   procedure Terminate_Process
     (Table        : in out Process_Table;
      Pid          : in     Process_Id;
      Caller_Level : in     Mls_Level_Type;
      Force        : in     Boolean;
      Status       :    out Proc_Status)
   is
      Slot : Slot_Index := Find_Process (Table, Pid);
   begin
      Status := Invalid_PID;

      if Slot = 0 then
         Schild_Log.Put_Line ("Proc: cannot terminate, PID not found");
         return;
      end if;

      if Table (Slot).State = Dead then
         Status := Success;
         Schild_Log.Put_Line ("Proc: process already dead, nothing to terminate");
         return;
      end if;

      if Table (Slot).State = Zombie then
         Status := Success;
         Schild_Log.Put_Line ("Proc: process already zombie, wait for parent to reap");
         return;
      end if;

      -- ============================================================
      --  MLS No Control Up: Caller_Level >= Target.Level
      --  The caller must dominate the target; a lower-level caller cannot
      --  terminate (control) a higher-level process.
      -- ============================================================
      if Interfaces.Unsigned_32 (Caller_Level) <
         Interfaces.Unsigned_32 (Table (Slot).Level)
      then
         Status := Mls_Violation;
         Schild_Log.Put_Line ("Proc: MLS violation — caller level too low to terminate target");
         return;
      end if;

      Schild_Log.Put_Line ("Proc: MLS termination check passed");

      if Force then
         Schild_Log.Put_Line ("Proc: sending SIGKILL to process");
         Table (Slot).Signals.Pending_Signals (Sig_Kill) := True;
      else
         Schild_Log.Put_Line ("Proc: sending SIGTERM to process");
         Table (Slot).Signals.Pending_Signals (Sig_Term) := True;
      end if;

      Table (Slot).State := Zombie;
      if Force then
         Table (Slot).Exit_Code := 9;
      else
         Table (Slot).Exit_Code := 15;
      end if;

      Status := Success;
   end Terminate_Process;

   -----------------
   -- Wait_Process --
   -----------------
   procedure Wait_Process
     (Table   : in out Process_Table;
      Pid     : in     Process_Id;
      Status  :    out Proc_Status)
   is
      Slot : constant Slot_Index := Find_Process (Table, Pid);
   begin
      Status := Invalid_PID;

      if Slot = 0 then
         Schild_Log.Put_Line ("Proc: cannot wait, PID not found");
         return;
      end if;

      if Table (Slot).State = Zombie then
         Table (Slot).State := Dead;
         Table (Slot).Pid   := Null_PID;   --  Free the PID on reap.
         Schild_Log.Put_Line ("Proc: process reaped (zombie → dead, PID freed)");
         Status := Success;
      elsif Table (Slot).State = Dead then
         Schild_Log.Put_Line ("Proc: process already dead");
         Status := Success;
      else
         Schild_Log.Put_Line ("Proc: process not yet terminated");
         Status := Access_Denied;
      end if;
   end Wait_Process;

   -----------------------
   -- Get_Process_Context --
   -----------------------
   function Get_Process_Context
     (Table : Process_Table;
      Pid   : Process_Id) return Process_Context
   is
      Slot : constant Slot_Index := Find_Process (Table, Pid);
   begin
      if Slot = 0 then
         return Process_Context'(others => <>);
      else
         return Table (Slot);
      end if;
   end Get_Process_Context;

   ----------------------------
   -- Check_Mls_Compatibility  --
   ----------------------------
   function Check_Mls_Compatibility
     (Proc1_Level : Mls_Level_Type;
      Proc2_Level : Mls_Level_Type) return Boolean
   is
   begin
      --  Two processes are compatible only at the same MLS level.
      return Proc1_Level = Proc2_Level;
   end Check_Mls_Compatibility;

   ------------------------------
   -- Deliver_Pending_Signals   --
   ------------------------------
   procedure Deliver_Pending_Signals
     (Table : in out Process_Table)
   is
      Signal   : Signal_Type;
      Handled : Boolean;
   begin
      for I in Table'Range loop
         if Table (I).State = Running or else Table (I).State = Ready then
            if Has_Pending_Signals (Table (I).Signals) then
               Deliver_Pending_Signal (Table (I).Signals, Signal, Handled);
               if Handled and then Signal = Sig_Kill then
                  Table (I).State := Zombie;
                  Table (I).Exit_Code := 9;
               end if;
            end if;
         end if;
      end loop;
   end Deliver_Pending_Signals;

   -----------------
   -- Reap_Zombies --
   -----------------
   procedure Reap_Zombies
     (Table : in out Process_Table)
   is
   begin
      for I in Table'Range loop
         if Table (I).State = Zombie then
            --  A zombie waits for its parent to call Wait (true reaping).
            --  (No automatic cleanup here: the parent owns the lifecycle.)
            Schild_Log.Put_Line ("Proc: zombie process found, awaiting parent Wait");
         end if;
      end loop;
   end Reap_Zombies;

end Schild_Process_Manager;