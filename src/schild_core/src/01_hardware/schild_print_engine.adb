with System;

package body Schild_Print_Engine with
  SPARK_Mode => Off --  UART output via the C bridge.
is

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   procedure Print_Debug_Message
     (Message : in     Log_String_Record;
      Success :    out Boolean)
   is
   begin
      --  Emit the first Message.Length characters to the UART.
      C_Putln (Message.Data'Address, Integer (Message.Length));
      Success := True;
   end Print_Debug_Message;

end Schild_Print_Engine;
