-- Schild TCB IDT Loader — initialization Interrupt Descriptor Table

with System;
with Interfaces;

package Schild_Idt_Loader with
  SPARK_Mode => Off
is
   --  Build and load the IDT (LIDT).
   procedure Init_Idt;

   --  Install an interrupt gate for a vector, with the given handler and DPL.
   procedure Set_Gate
     (Vector   : in Interfaces.Unsigned_32;
      Handler  : in System.Address;
      DPL      : in Interfaces.Unsigned_8 := 0);

end Schild_Idt_Loader;
