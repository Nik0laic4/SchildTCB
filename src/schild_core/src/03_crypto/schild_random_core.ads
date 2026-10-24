with Interfaces;

package Schild_Random_Core with
  SPARK_Mode => Off
is

   --  Result of a hardware draw: raw value plus health/freshness flags.
   type Random_Passport is record
      Raw_Value      : Interfaces.Unsigned_64;
      Is_Hardware_Ok : Boolean;
      Is_Fresh       : Boolean;
   end record;

   --  Draw one 64-bit value from the on-CPU hardware RNG (RDRAND).
   procedure Get_Hardware_Random
     (Passport : out Random_Passport;
      Success  : out Boolean)
   with
     --  Global => null: the draw reads no package or global state.
     --  The target CPU must expose the RDRAND instruction (checked at runtime).
     --  A successful draw reports a healthy, fresh value.
     Post => (if Success then Passport.Is_Hardware_Ok and Passport.Is_Fresh);

end Schild_Random_Core;
