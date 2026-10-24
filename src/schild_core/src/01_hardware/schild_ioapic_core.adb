pragma Spark_Mode (On);

package body Schild_Ioapic_Core is

   procedure Compose_Redirection_Entry
     (Vector         : in     Vector_Type;
      Target_Apic_ID : in     Apic_ID_Type;
      Entry_Value    :    out Redirection_Entry_64;
      Is_Valid       :    out Boolean)
   is
      Result : Redirection_Entry_64;
   begin
      if Vector >= MIN_HARDWARE_VECTOR and then
         Vector <= MAX_HARDWARE_VECTOR and then
         Target_Apic_ID <= MAX_CORE_ID
      then
         --  Compose the redirection entry.
         Result := Redirection_Entry_64(Vector);
         Result := Result + (Redirection_Entry_64(Target_Apic_ID) * 2**56);
         
         Entry_Value := Result;
         Is_Valid    := True;
      else
         Entry_Value := 0;
         Is_Valid    := False;
      end if;
   end Compose_Redirection_Entry;

end Schild_Ioapic_Core;
