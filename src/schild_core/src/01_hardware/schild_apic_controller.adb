pragma Spark_Mode (On);

package body Schild_Apic_Controller is

   procedure Configure_Apic_Timer
     (Vector   : in     Interfaces.Unsigned_8;
      Mask_Irq : in     Boolean;
      Config   :    out Apic_Config_Record;
      Success  :    out Boolean)
   is
   begin
      if Vector >= 32 then
         Config.Timer_Vector := Vector;
         Config.Is_Masked    := Mask_Irq;
         Success             := True;
      else
         Config  := (Timer_Vector => 0, Is_Masked => True);
         Success := False;
      end if;
   end Configure_Apic_Timer;

end Schild_Apic_Controller;
