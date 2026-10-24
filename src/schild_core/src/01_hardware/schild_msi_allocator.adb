pragma Spark_Mode (On);

package body Schild_Msi_Allocator is

   procedure Allocate_Msi_Vector
     (Vector         : in     Vector_Type;
      Target_Apic_ID : in     Apic_ID_Type;
      Msg_Address    :    out Msg_Address_64;
      Msg_Data       :    out Msg_Data_32;
      Is_Alloc_Valid :    out Boolean)
   is
   begin
      if Vector >= MIN_HW_VECTOR and then Vector <= MAX_HW_VECTOR then
         --  Address = base + (APIC id << 12).
         Msg_Address := APIC_BASE_DELIVERY_ADDR + (Msg_Address_64(Target_Apic_ID) * 2**12);
         
         --  Data carries the vector.
         Msg_Data := Msg_Data_32(Vector);
         
         Is_Alloc_Valid := True;
      else
         Msg_Address    := 0;
         Msg_Data       := 0;
         Is_Alloc_Valid := False;
      end if;
   end Allocate_Msi_Vector;

end Schild_Msi_Allocator;
