package body Schild_Tss_Layout with
  SPARK_Mode => On --  Lay out the TSS RSP0 entry.
is

   procedure Build_Tss_Layout
     (Rsp0_Addr  : in     Unsigned_64;
      Tss_Struct :    out Tss_Structure_Array;
      Passport   :    out Tss_Layout_Passport;
      Success    :    out Boolean)
   is
      --  Split RSP0 into low and high 32-bit halves.
      Low_Part  : constant Unsigned_32 := Unsigned_32 (Rsp0_Addr and 16#FFFF_FFFF#);
      --  High 32 bits.
      High_Part : constant Unsigned_32 := Unsigned_32 (Shift_Right (Rsp0_Addr, 32) and 16#FFFF_FFFF#);
   begin
      --  Zero the TSS, then fill the RSP0 slots (words 2/3).
      Tss_Struct := (others => 0);
      Tss_Struct (2) := Low_Part;
      Tss_Struct (3) := High_Part;

      --  Record the bounds for the passport.
      Passport := (Rsp0_Low_Bound  => Low_Part,
                   Rsp0_High_Bound => High_Part);

      Success := True;
   end Build_Tss_Layout;

end Schild_Tss_Layout;
