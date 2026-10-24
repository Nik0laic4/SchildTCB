pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Aes_Key_Expander is

   type Key_Size_Type is range 0 .. 512;
   type Schedule_Size_Type is range 0 .. 512;
   type Key_Schedule_Type is array (0 .. 14) of Unsigned_32;

   AES_256_KEY_SIZE      : constant Key_Size_Type := 32;
   AES_256_SCHEDULE_SIZE : constant Schedule_Size_Type := 240;

   procedure Validate_Key_Expansion
     (Input_Key_Size      : in     Key_Size_Type;
      Output_Schedule_Size : in     Schedule_Size_Type;
      Is_Schedule_Safe     :    out Boolean)
   with
     Global  => null,
     Post    => Is_Schedule_Safe = (Input_Key_Size = AES_256_KEY_SIZE and then
                                    Output_Schedule_Size = AES_256_SCHEDULE_SIZE);

   procedure Expand_Master_Key
     (Master_Key   : in     Unsigned_32;
      Schedule_Ctx :    out Key_Schedule_Type;
      Success      :    out Boolean)
   with
     Global => null;

end Schild_Aes_Key_Expander;
