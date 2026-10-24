pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Apic_Controller is

   type Apic_Config_Record is record
      Timer_Vector : Unsigned_8;
      Is_Masked    : Boolean;
   end record;

   procedure Configure_Apic_Timer
     (Vector   : in     Unsigned_8;
      Mask_Irq : in     Boolean;
      Config   :    out Apic_Config_Record;
      Success  :    out Boolean)
   with
     Global => null,
     Pre    => Vector >= 32,
     Post   => (if Success then Config.Timer_Vector = Vector and Config.Is_Masked = Mask_Irq);

end Schild_Apic_Controller;
