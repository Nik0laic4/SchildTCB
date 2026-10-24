package Schild_Apic_Core with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   procedure Signal_Apic_Mfence;
   procedure Configure_Apic_Lvt;

end Schild_Apic_Core;
