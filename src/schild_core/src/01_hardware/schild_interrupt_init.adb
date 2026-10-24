--  Installs default interrupt handlers for vectors 0..255.

with Schild_Idt_Loader;
with System;
with Interfaces;
use type System.Address;
with Schild_Uart_Driver;

package body Schild_Interrupt_Init with
  SPARK_Mode => Off
is
   use Interfaces;

   --  Per-vector handler addresses.
   Interrupt_Vectors : array (Unsigned_32 range 0 .. 255) of System.Address;
   pragma Import (C, Interrupt_Vectors, "schild_interrupt_vectors");

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   Msg_Idt : constant String := "[INTR] IDT loaded, interrupts initialized";

   procedure Init_All is
   begin
      -- 1. Load IDT
      Schild_Idt_Loader.Init_Idt;

      -- 2. Register CPU exception handlers CPU
      for Vec in Unsigned_32 range 0 .. 31 loop
         if Interrupt_Vectors (Vec) /= System.Null_Address then
            Schild_Idt_Loader.Set_Gate (Vec, Interrupt_Vectors (Vec), 0);
         end if;
      end loop;

      --  Bind each wired IRQ to its handler.
      for IRQ in Unsigned_32 range 0 .. 15 loop
         declare
            Vec : constant Unsigned_32 := 16#20# + IRQ;
         begin
            if Interrupt_Vectors (Vec) /= System.Null_Address then
               Schild_Idt_Loader.Set_Gate (Vec, Interrupt_Vectors (Vec), 0);
            end if;
         end;
      end loop;

      C_Putln (Msg_Idt'Address, Msg_Idt'Length);
   end Init_All;

end Schild_Interrupt_Init;
