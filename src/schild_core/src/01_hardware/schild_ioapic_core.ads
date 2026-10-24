pragma Spark_Mode (On);

package Schild_Ioapic_Core is

   type Irq_Line_Type is range 0 .. 23;
   type Vector_Type is range 0 .. 255;
   type Apic_ID_Type is mod 2**8;
   type Redirection_Entry_64 is mod 2**64;

   --  Vectors below 32 are reserved for CPU exceptions.
   MIN_HARDWARE_VECTOR : constant Vector_Type := 32;
   MAX_HARDWARE_VECTOR : constant Vector_Type := 255;

   --  Maximum local APIC id supported.
   MAX_CORE_ID : constant Apic_ID_Type := 16;

   --  Build an IOAPIC redirection entry (vector, destination, mode).
   procedure Compose_Redirection_Entry
     (Vector         : in     Vector_Type;
      Target_Apic_ID : in     Apic_ID_Type;
      Entry_Value    :    out Redirection_Entry_64;
      Is_Valid       :    out Boolean)
   with
     Global  => null,
     Depends => (Entry_Value => (Vector, Target_Apic_ID), Is_Valid => (Vector, Target_Apic_ID)),
     Post    => (if Is_Valid then
                   Vector >= MIN_HARDWARE_VECTOR and
                   Vector <= MAX_HARDWARE_VECTOR and
                   Target_Apic_ID <= MAX_CORE_ID and
                   Entry_Value = Redirection_Entry_64(Vector) + (Redirection_Entry_64(Target_Apic_ID) * 2**56)
                 else
                   Vector < MIN_HARDWARE_VECTOR or
                   Vector > MAX_HARDWARE_VECTOR or
                   Target_Apic_ID > MAX_CORE_ID);

end Schild_Ioapic_Core;
