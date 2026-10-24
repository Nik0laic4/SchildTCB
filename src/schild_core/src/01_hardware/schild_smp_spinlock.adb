with System.Machine_Code; use System.Machine_Code;
with Interfaces;          use Interfaces;

package body Schild_Smp_Spinlock with
  SPARK_Mode => Off --  Atomic primitives via inline asm: outside SPARK's model.
is

   Locked_Value   : constant Unsigned_32 := 1;
   Unlocked_Value : constant Unsigned_32 := 0;

   --  Atomically exchange Word <-> Value; returns the previous value in Old.
   --  XCHG with a memory operand is implicitly atomic on x86 (no LOCK needed).
   procedure Atomic_Exchange
     (Word  : in out Unsigned_32;
      Value : in     Unsigned_32;
      Old   :    out Unsigned_32)
   is
   begin
      Asm (Template => "xchgl %0, %1",
           Outputs  => (Unsigned_32'Asm_Output ("=a", Old),
                        Unsigned_32'Asm_Output ("+m", Word)),
           Inputs   => Unsigned_32'Asm_Input ("0", Value),
           Volatile => True);
   end Atomic_Exchange;

   procedure Acquire_Lock
     (Lock : in out Spinlock_State;
      Core : in     Core_Id_Type)
   is
      Old : Unsigned_32;
   begin
      loop
         Atomic_Exchange (Lock.Word, Locked_Value, Old);
         exit when Old = Unlocked_Value;
         Asm (Template => "pause", Volatile => True);
      end loop;
      Lock.Owner_Core := Core;
      Asm (Template => "mfence", Volatile => True);
   end Acquire_Lock;

   procedure Release_Lock
     (Lock : in out Spinlock_State;
      Core : in     Core_Id_Type)
   is
      pragma Unreferenced (Core);
   begin
      Asm (Template => "mfence", Volatile => True);
      Lock.Word := Unlocked_Value;
   end Release_Lock;

end Schild_Smp_Spinlock;
