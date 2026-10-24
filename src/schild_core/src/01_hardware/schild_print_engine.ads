with Interfaces; use Interfaces;

package Schild_Print_Engine with
  SPARK_Mode => On
is

   subtype Log_Message_Length is Positive range 1 .. 128;
   type Log_String_Record is record
      Length : Log_Message_Length := 1;
      Data   : String (1 .. 128) := (others => ' ');
   end record;

   procedure Print_Debug_Message
     (Message : in     Log_String_Record;
      Success :    out Boolean)
   with Pre => Message.Length > 0;

end Schild_Print_Engine;
