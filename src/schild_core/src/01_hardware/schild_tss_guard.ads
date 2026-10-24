with Interfaces; use Interfaces;

package Schild_Tss_Guard with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

    subtype Tss_Address_Type is Interfaces.Unsigned_64;
   
   --  A valid TSS is at least 104 bytes.
   Tss_Minimum_Limit : constant Interfaces.Unsigned_16 := 104;

   type Tss_Descriptor_Record is record
      Base_Addr : Tss_Address_Type := 0;
      Limit     : Interfaces.Unsigned_16 := 0;
      Is_Busy   : Boolean := False;
   end record;

   procedure Validate_Tss_Descriptor
     (Descriptor : in     Tss_Descriptor_Record;
      Valid      :    out Boolean)
   with Post => (if Valid then Descriptor.Limit >= Tss_Minimum_Limit 
                 and (Descriptor.Base_Addr and 16#F#) = 0);
   --  The base must be 16-byte aligned.

end Schild_Tss_Guard;
