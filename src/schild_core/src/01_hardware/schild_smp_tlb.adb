with System.Machine_Code; use System.Machine_Code;
with Interfaces;          use Interfaces;

package body Schild_Smp_Tlb with
  SPARK_Mode => Off --  INVLPG primitive via inline asm.
is

   procedure Broadcast_Tlb_Shootdown
     (Message : in out Tlb_Message_Record;
      Success :    out Boolean)
   is
      Addr : Unsigned_64 := Unsigned_64 (Message.Page_To_Flush);
   begin
      --  INVLPG invalidates the TLB entry for the target virtual page on the
      --  current core. Full cross-core broadcast additionally requires an APIC
      --  IPI (separate concern); this is the real local invalidation.
      Asm (Template => "invlpg (%0)",
           Inputs    => Unsigned_64'Asm_Input ("r", Addr),
           Volatile  => True);
      Asm (Template => "mfence", Volatile => True);
      Message.Status := Tlb_Invalidated;
      Success := True;
   end Broadcast_Tlb_Shootdown;

end Schild_Smp_Tlb;
