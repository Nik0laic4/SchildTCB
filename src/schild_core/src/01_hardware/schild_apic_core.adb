with System.Machine_Code; use System.Machine_Code;

package body Schild_Apic_Core with
  SPARK_Mode => Off --  APIC register scaffold.
is

   procedure Signal_Apic_Mfence is
   begin
      System.Machine_Code.Asm (Template => "mfence", Volatile => True);
   end Signal_Apic_Mfence;

   procedure Configure_Apic_Lvt is
   begin
      System.Machine_Code.Asm (Template => "mfence", Volatile => True);
   end Configure_Apic_Lvt;

end Schild_Apic_Core;
