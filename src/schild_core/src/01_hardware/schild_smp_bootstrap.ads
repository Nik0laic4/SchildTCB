-- Schild TCB SMP Bootstrap — v0.5.0
with System; with Interfaces;

package Schild_Smp_Bootstrap with SPARK_Mode => Off is
   use Interfaces;

   procedure Init;
   function Get_Cpu_Count return Unsigned_32;
   function Get_Bsp_Apic_Id return Unsigned_8;
private
   procedure Start_Ap (Apic_Id : Unsigned_8; Cpu_Idx : Positive);
   procedure Ap_Entry (Cpu_Id : Unsigned_32);
   pragma Export (C, Ap_Entry, "schild_smp_ap_entry");
end Schild_Smp_Bootstrap;
