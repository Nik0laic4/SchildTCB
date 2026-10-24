package body Schild_Mmap_Parser with
  SPARK_Mode => Off --  Multiboot memory-map parser.
is

   procedure Validate_Memory_Entry
     (Entry_Data : in     Mmap_Entry_Record;
      Is_Safe    :    out Boolean)
   is
   begin
      --  Count available, non-zero-based regions.
      if Entry_Data.Zone_Type = Region_Available and Entry_Data.Base_Addr /= 0 then
         Is_Safe := True;
      else
         Is_Safe := False;
      end if;
   end Validate_Memory_Entry;

end Schild_Mmap_Parser;
