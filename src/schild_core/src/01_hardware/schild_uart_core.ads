pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Uart_Core is

   type Uart_Passport_Record is record
      Is_Tx_Ready : Boolean;
      Byte_Sent   : Unsigned_8;
   end record;

   --  TX passport alias.
   subtype Uart_Tx_Passport is Uart_Passport_Record;

   procedure Write_Uart_Byte
     (Data     : in     Unsigned_8;
      Passport : in out Uart_Passport_Record;
      Success  :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Tx_Ready = True
                and Passport.Byte_Sent = Data);

   --  Write one byte to the serial port.
   procedure Write_Serial_Byte
     (Data     : in     Unsigned_8;
      Passport : in out Uart_Tx_Passport;
      Success  :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Tx_Ready = True
                and Passport.Byte_Sent = Data);

end Schild_Uart_Core;
