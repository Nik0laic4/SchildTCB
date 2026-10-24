pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Uart_Core is

   procedure Write_Uart_Byte
     (Data     : in     Unsigned_8;
      Passport : in out Uart_Passport_Record;
      Success  :    out Boolean)
   is
   begin
      Passport.Byte_Sent   := Data;
      Passport.Is_Tx_Ready := True;
      Success              := True;
   end Write_Uart_Byte;

   procedure Write_Serial_Byte
     (Data     : in     Unsigned_8;
      Passport : in out Uart_Tx_Passport;
      Success  :    out Boolean)
   is
   begin
      Passport.Byte_Sent   := Data;
      Passport.Is_Tx_Ready := True;
      Success              := True;
   end Write_Serial_Byte;

end Schild_Uart_Core;
