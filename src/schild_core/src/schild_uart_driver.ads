-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

--  Schild TCB - UART driver (16550 COM1 at 0x3F8).

with Interfaces;

package Schild_Uart_Driver with
  SPARK_Mode => On
is

   UART_Port : constant Integer := 16#03F8#;

   --  Configure the UART baud/line settings.
   procedure Init_Uart;

   procedure Put_Char (C : Character);
   procedure Put_String (Text : String);
   procedure Put_Line (Text : String);

end Schild_Uart_Driver;
