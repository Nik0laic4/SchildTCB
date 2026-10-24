package body Schild_Tss_Guard with
  SPARK_Mode => On
is

   procedure Validate_Tss_Descriptor
     (Descriptor : in     Tss_Descriptor_Record;
      Valid      :    out Boolean)
   is
   begin
      --  The TSS must meet the minimum size and be present.
      if Descriptor.Limit >= Tss_Minimum_Limit and then
         (Descriptor.Base_Addr and 16#F#) = 0
      then
         Valid := True;
      else
         Valid := False;
      end if;
   end Validate_Tss_Descriptor;

end Schild_Tss_Guard;
