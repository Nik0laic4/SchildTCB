with Interfaces;
with Schild_Apic_Controller;
with Schild_Smp_Balancer;

package Schild_Ioapic_Core with
  SPARK_Mode => On
is

   --  24 IRQ lines on the IOAPIC.
   subtype Ioapic_Irq_Range is Natural range 0 .. 23;

   --  Register-select and register-window indices.
   Ioapic_Reg_Index : constant Interfaces.Unsigned_32 := 16#0000#; -- Register Select
   Ioapic_Reg_Data  : constant Interfaces.Unsigned_32 := 16#0010#; -- Register Window

   --  Base of the redirection table.
   Ioapic_Redtbl_Base : constant Interfaces.Unsigned_32 := 16#0010#;

   --  Result of composing a redirection entry.
   type Ioapic_Route_Passport is record
      Low_32_Bits     : Interfaces.Unsigned_32;
      High_32_Bits    : Interfaces.Unsigned_32;
      Assigned_Vector : Schild_Apic_Controller.Valid_Apic_Vector;
      Target_Cpu_Id   : Schild_Smp_Balancer.Core_Id_Type;
      Is_Masked       : Boolean;
   end record;

   --  Build a 64-bit redirection entry.
   procedure Compute_Redirection_Entry
     (Irq      : in Ioapic_Irq_Range;
      Vector   : in Schild_Apic_Controller.Valid_Apic_Vector;
      Target_Core : in Schild_Smp_Balancer.Core_Id_Type;
      Mask_Irq : in Boolean;
      Passport : out Ioapic_Route_Passport;
      Success  : out Boolean)
   with
     --  On success the entry carries the vector, target and mask state.
     Post => (if Success then 
                Passport.Assigned_Vector = Vector
                and Passport.Target_Cpu_Id = Target_Core
                and Passport.Is_Masked = Mask_Irq
                and (Passport.Low_32_Bits and 16#FF#) = Interfaces.Unsigned_32 (Vector)
                and (if Mask_Irq then (Passport.Low_32_Bits and 16#0001_0000#) = 16#0001_0000#));

end Schild_Ioapic_Core;
