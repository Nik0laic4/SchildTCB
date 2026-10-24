with Interfaces;
use type Interfaces.Unsigned_64;
use type Interfaces.Unsigned_32;

package Schild_Vmx_Context_Guard with SPARK_Mode => On is

   --  VMCS must sit above 4 MB.
   Kernel_Memory_Limit : constant Interfaces.Unsigned_64 := 16#0040_0000#;
   
   --  VMCS must sit below the top of physical memory.
   Max_Physical_Address : constant Interfaces.Unsigned_64 := 16#000F_FFFF_FFFF_F000#;

   type Vmx_Context_Record is record
      Vmcs_Pointer   : Interfaces.Unsigned_64 := 0;
      Owner_PID      : Interfaces.Unsigned_32 := 0;
      Is_Vmx_Enabled : Boolean := False;
      Is_Active      : Boolean := False;
   end record;

   --  Validate a VMX transition (owner, range, alignment).
   procedure Validate_Vmx_Transition
     (Context    : Vmx_Context_Record;
      Caller_PID : Interfaces.Unsigned_32;
      Allowed    : out Boolean)
   with
     Post => (if Allowed then 
                Context.Is_Active 
                and Context.Is_Vmx_Enabled
                and Context.Owner_PID = Caller_PID 
                and Context.Vmcs_Pointer >= Kernel_Memory_Limit
                and Context.Vmcs_Pointer <= Max_Physical_Address
                and (Context.Vmcs_Pointer and 16#FFF#) = 0); --  4 KiB-aligned.

end Schild_Vmx_Context_Guard;
