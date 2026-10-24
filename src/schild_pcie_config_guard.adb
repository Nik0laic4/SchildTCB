with System.Machine_Code; use System.Machine_Code;

package body Schild_Pcie_Config_Guard with
  SPARK_Mode => On
is

   --------------------------
   -- Compute_Ecam_Address --
   --------------------------
   procedure Compute_Ecam_Address
     (Bus      : in Pcie_Bus_Range;
      Device   : in Pcie_Device_Range;
      Func     : in Pcie_Function_Range;
      Register : in Pcie_Register_Range;
      Passport : out Pcie_Access_Passport;
      Success  : out Boolean)
   is
      use type Interfaces.Unsigned_64;
      
      --  Start from a zeroed offset.
      Offset : Interfaces.Unsigned_64 := 0;
   begin
      --  Start from a failed passport.
      Passport := (Physical_Config_Addr => 0, Is_Within_Ecam_Range => False, Is_Aligned => False);
      Success  := False;

      --  Fence before the address computation.
      Asm (Template => "lfence", Volatile => True);

      --  Offset = (bus << 20) | (dev << 15) | (func << 12) | reg.
      Offset := Interfaces.Shift_Left (Interfaces.Unsigned_64 (Bus), 20) or
                Interfaces.Shift_Left (Interfaces.Unsigned_64 (Device), 15) or
                Interfaces.Shift_Left (Interfaces.Unsigned_64 (Func), 12) or
                Interfaces.Unsigned_64 (Register);

      --  Reject offsets outside the ECAM window.
      if Offset < Pcie_Ecam_Size then
         Passport.Physical_Config_Addr := Schild_Mmio_Mapper.Pcie_Ecft_Physical + Offset;
         Passport.Is_Within_Ecam_Range := True;
         
         --  Require 4-byte alignment.
         if (Passport.Physical_Config_Addr and 16#03#) = 0 then
            Passport.Is_Aligned := True;
            Success            := True;
         end if;
      end if;

      Asm (Template => "lfence", Volatile => True);
   end Compute_Ecam_Address;

end Schild_Pcie_Config_Guard;
