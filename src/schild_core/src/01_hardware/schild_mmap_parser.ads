with Interfaces; use Interfaces;

package Schild_Mmap_Parser with
  SPARK_Mode => On
is

   type Physical_Frame_Address is new Interfaces.Unsigned_64;
   type Memory_Region_Type is (Region_Available, Region_Reserved, Region_Acpi, Region_Unusable);

   type Mmap_Entry_Record is record
      Base_Addr : Physical_Frame_Address := 0;
      Length    : Interfaces.Unsigned_64 := 0;
      Zone_Type : Memory_Region_Type := Region_Reserved;
   end record;

   procedure Validate_Memory_Entry
     (Entry_Data : in     Mmap_Entry_Record;
      Is_Safe    :    out Boolean)
   with Pre => Entry_Data.Length > 0,
        Post => (if Is_Safe then Entry_Data.Zone_Type = Region_Available);

end Schild_Mmap_Parser;
