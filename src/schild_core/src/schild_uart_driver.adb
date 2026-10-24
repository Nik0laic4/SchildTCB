-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

--  Schild TCB - UART driver body (16550 COM1).
--  Wraps outb for register access and delegates string output to C helpers.

with System;
with System.Machine_Code;

package body Schild_Uart_Driver with
  SPARK_Mode => Off  -- inline asm + C import
is

   -- C function: outputs len bytes from Addr, no trailing newline
   procedure C_Puts (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Puts, "schild_uart_puts");

   -- C function: outputs len bytes from Addr, appends CR+LF
   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   procedure Out_Byte (Port : Integer; Value : Interfaces.Unsigned_8) is
      use System.Machine_Code;
   begin
      Asm (Template  => "outb %0, %1",
           Outputs   => No_Output_Operands,
           Inputs    => (Interfaces.Unsigned_8'Asm_Input ("a", Value),
                         Integer'Asm_Input          ("Nd", Port)),
           Volatile  => True);
   end Out_Byte;

   ---------------
   -- Init_Uart --
   ---------------
   procedure Init_Uart is
   begin
      Out_Byte (UART_Port + 1, 16#00#);
      Out_Byte (UART_Port + 3, 16#80#);
      Out_Byte (UART_Port + 0, 16#03#);
      Out_Byte (UART_Port + 1, 16#00#);
      Out_Byte (UART_Port + 3, 16#03#);
      Out_Byte (UART_Port + 2, 16#C7#);
   end Init_Uart;

   procedure Put_Char (C : Character) is
   begin
      Out_Byte (UART_Port, Interfaces.Unsigned_8 (Character'Pos (C)));
   end Put_Char;

   procedure Put_String (Text : String) is
   begin
      C_Puts (Text'Address, Text'Length);
   end Put_String;

   procedure Put_Line (Text : String) is
   begin
      C_Putln (Text'Address, Text'Length);
   end Put_Line;

end Schild_Uart_Driver;
