pragma Spark_Mode (On);

package body Schild_Aes_Key_Expander is

   procedure Validate_Key_Expansion
     (Input_Key_Size      : in     Key_Size_Type;
      Output_Schedule_Size : in     Schedule_Size_Type;
      Is_Schedule_Safe     :    out Boolean)
   is
   begin
      Is_Schedule_Safe := (Input_Key_Size = AES_256_KEY_SIZE and then
                           Output_Schedule_Size = AES_256_SCHEDULE_SIZE);
   end Validate_Key_Expansion;

   procedure Expand_Master_Key
     (Master_Key   : in     Unsigned_32;
      Schedule_Ctx :    out Key_Schedule_Type;
      Success      :    out Boolean)
   is
   begin
      Schedule_Ctx := (others => Master_Key);
      Success      := True;
   end Expand_Master_Key;

end Schild_Aes_Key_Expander;
