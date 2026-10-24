package Schild_Interrupts with SPARK_Mode is

   --  Number of wired IRQ lines.
   Max_IRQ : constant := 16;
   type IRQ_Index is range 1 .. Max_IRQ;

   --  An IRQ line is either pending or inactive.
   type IRQ_State is (IRQ_Inactive, IRQ_Pending);

   --  Bitmap of pending IRQ lines.
   type Interrupt_Mask is array (IRQ_Index) of IRQ_State;

   --  A simple interrupt controller: pending mask + active count.
   type Interrupt_Controller is record
      Pending_Mask : Interrupt_Mask := (others => IRQ_Inactive);
      Active_Count : Integer range 0 .. Max_IRQ := 0; --  Number of currently pending IRQs.
   end record;

   --  Mark an IRQ pending. Only one pending IRQ per line is allowed, and the
   --  controller must not already be saturated.
   procedure Hardware_Trigger (Controller : in out Interrupt_Controller; IRQ : IRQ_Index)
     with Pre  => Controller.Active_Count < Max_IRQ and then 
                  Controller.Pending_Mask (IRQ) = IRQ_Inactive,
          Post => Controller.Active_Count = Controller.Active_Count'Old + 1 and then
                  Controller.Pending_Mask (IRQ) = IRQ_Pending;

   --  Acknowledge an IRQ, returning it to inactive and decrementing the count.
   procedure Clear_Interrupt (Controller : in out Interrupt_Controller; IRQ : IRQ_Index)
     with Pre  => Controller.Active_Count > 0 and then
                  Controller.Pending_Mask (IRQ) = IRQ_Pending,
          Post => Controller.Active_Count = Controller.Active_Count'Old - 1 and then
                  Controller.Pending_Mask (IRQ) = IRQ_Inactive;

end Schild_Interrupts;
