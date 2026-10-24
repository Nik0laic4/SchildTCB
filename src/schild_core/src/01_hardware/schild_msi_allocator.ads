pragma Spark_Mode (On);

package Schild_Msi_Allocator is

   type Msg_Address_64 is mod 2**64;
   type Msg_Data_32    is mod 2**32;
   type Vector_Type    is range 0 .. 255;
   type Apic_ID_Type   is mod 2**8;

   --  Base address of the xAPIC message delivery window.
   APIC_BASE_DELIVERY_ADDR : constant Msg_Address_64 := 16#0000_0000_FEE0_0000#;
   
   --  Mask isolating the APIC base address field.
   APIC_ADDR_MASK          : constant Msg_Address_64 := 16#FFFF_FFFF_FFF0_0000#;

   --  Vectors 32..255 are available for MSI/MSI-X.
   MIN_HW_VECTOR : constant Vector_Type := 32;
   MAX_HW_VECTOR : constant Vector_Type := 255;

   --  Compute the MSI address/data for a vector and target APIC.
   procedure Allocate_Msi_Vector
     (Vector         : in     Vector_Type;
      Target_Apic_ID : in     Apic_ID_Type;
      Msg_Address    :    out Msg_Address_64;
      Msg_Data       :    out Msg_Data_32;
      Is_Alloc_Valid :    out Boolean)
   with
     Global  => null,
     Depends => (Msg_Address    => (Target_Apic_ID, Vector), --  Address depends on target + vector.
                 Msg_Data       => Vector,
                 Is_Alloc_Valid => Vector),
     Post    => (if Is_Alloc_Valid then
                   (Msg_Address and APIC_ADDR_MASK) = APIC_BASE_DELIVERY_ADDR and
                   Vector >= MIN_HW_VECTOR and Vector <= MAX_HW_VECTOR and
                   Msg_Data = Msg_Data_32(Vector)
                 else
                   Vector < MIN_HW_VECTOR or Vector > MAX_HW_VECTOR);

end Schild_Msi_Allocator;
