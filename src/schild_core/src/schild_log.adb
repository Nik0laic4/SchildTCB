-- Schild TCB — observability abstraction (platform side).
-- SPARK_Mode => Off: forwards to the UART driver. Only the *contract* above
-- is trusted by the proof; this body is ordinary platform code.

with Schild_Uart_Driver;

package body Schild_Log with
  SPARK_Mode => Off
is
   procedure Put_String (Text : String) is
   begin
      Schild_Uart_Driver.Put_String (Text);
   end Put_String;

   procedure Put_Line (Text : String) is
   begin
      Schild_Uart_Driver.Put_Line (Text);
   end Put_Line;
end Schild_Log;
