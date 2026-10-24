package body Schild_Hardware with SPARK_Mode is

   procedure Write_Char
     (Screen : in out VGA_Screen;
      Char   :        Hardware_Byte;
      Color  :        Hardware_Byte) is
   begin
      --  Write the character cell at the cursor.
      Screen.Memory (Screen.Cursor) := Char;
      
      --  Write its attribute byte.
      Screen.Memory (Screen.Cursor + 1) := Color;
      
      --  Advance the cursor two cells.
      Screen.Cursor := Screen.Cursor + 2;
   end Write_Char;

end Schild_Hardware;
