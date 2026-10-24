package body Schild_Vmx_Context_Guard with SPARK_Mode => On is

   -----------------------------
   -- Validate_Vmx_Transition --
   -----------------------------
   procedure Validate_Vmx_Transition
     (Context    : Vmx_Context_Record;
      Caller_PID : Interfaces.Unsigned_32;
      Allowed    : out Boolean) is
   begin
      --  VMX must be active and enabled.
      if not Context.Is_Active or else not Context.Is_Vmx_Enabled then
         Allowed := False;
         return;
      end if;

      --  Only the owner may transition.
      if Context.Owner_PID /= Caller_PID then
         Allowed := False;
         return;
      end if;

      --  Reject VMCS pointers outside the valid range.
      if Context.Vmcs_Pointer < Kernel_Memory_Limit or else Context.Vmcs_Pointer > Max_Physical_Address then
         Allowed := False;
         return;
      end if;

      --  Reject misaligned VMCS pointers.
      if (Context.Vmcs_Pointer and 16#FFF#) /= 0 then
         Allowed := False;
         return;
      end if;

      --  All checks passed.
      Allowed := True;
   end Validate_Vmx_Transition;

end Schild_Vmx_Context_Guard;
