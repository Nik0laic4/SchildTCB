with System.Machine_Code; use System.Machine_Code;

package body Schild_Ioapic_Core with
  SPARK_Mode => On
is

   -------------------------------
   -- Compute_Redirection_Entry --
   -------------------------------
   procedure Compute_Redirection_Entry
     (Irq      : in Ioapic_Irq_Range;
      Vector   : in Schild_Apic_Controller.Valid_Apic_Vector;
      Target_Core : in Schild_Smp_Balancer.Core_Id_Type;
      Mask_Irq : in Boolean;
      Passport : out Ioapic_Route_Passport;
      Success  : out Boolean)
   is
      use type Interfaces.Unsigned_32;
      
      Low_Val  : Interfaces.Unsigned_32 := 0;
      High_Val : Interfaces.Unsigned_32 := 0;
   begin
      --  Start from a masked, default entry.
      Passport := (Low_32_Bits => 0, High_32_Bits => 0, Assigned_Vector => 32, Target_Cpu_Id => 0, Is_Masked => True);
      Success  := False;

      --  Fence before composing the entry.
      Asm (Template => "mfence", Volatile => True);

      --  The low word starts with the vector.
      Low_Val := Interfaces.Unsigned_32 (Vector);

      --  (Delivery mode and destination-mode bits stay clear.)

      --  Set the interrupt-mask bit when requested.
      if Mask_Irq then
         Low_Val := Low_Val or 16#0001_0000#;
      end if;

      --  The high word holds the destination (APIC id << 24).
      High_Val := Interfaces.Shift_Left (Interfaces.Unsigned_32 (Target_Core), 24);

      Passport.Low_32_Bits     := Low_Val;
      Passport.High_32_Bits    := High_Val;
      Passport.Assigned_Vector := Vector;
      Passport.Target_Cpu_Id   := Target_Core;
      Passport.Is_Masked       := Mask_Irq;
      Success                  := True;

      Asm (Template => "mfence", Volatile => True);
   end Compute_Redirection_Entry;

end Schild_Ioapic_Core;
