with System.Machine_Code; use System.Machine_Code;

package body Schild_Smp_Panic with
  SPARK_Mode => Off --  Panic halts the core.
is

   procedure Trigger_Smp_Cascade_Panic
     (Faulty_Core : in     Schild_Smp_Spinlock.Core_Id_Type;
      Reason      : in     Crash_Reason_Code)
   is
   begin
      -- Cascade stop of all cores CPU cluster via barrier mfence
      loop
         System.Machine_Code.Asm (Template => "mfence", Volatile => True);
         --  mfence before re-checking the panic flag.
      end loop;
   end Trigger_Smp_Cascade_Panic;

end Schild_Smp_Panic;
