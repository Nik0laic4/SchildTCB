package body Schild_Interrupts with SPARK_Mode is

   procedure Hardware_Trigger (Controller : in out Interrupt_Controller; IRQ : IRQ_Index) is
   begin
      Controller.Pending_Mask (IRQ) := IRQ_Pending;
      Controller.Active_Count       := Controller.Active_Count + 1;
   end Hardware_Trigger;

   procedure Clear_Interrupt (Controller : in out Interrupt_Controller; IRQ : IRQ_Index) is
   begin
      Controller.Pending_Mask (IRQ) := IRQ_Inactive;
      Controller.Active_Count       := Controller.Active_Count - 1;
   end Clear_Interrupt;

end Schild_Interrupts;
