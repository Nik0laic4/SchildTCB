pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Msr_Syscall_Core is

   type Msr_Syscall_Passport is record
      Star_Value  : Unsigned_64;
      Lstar_Value : Unsigned_64;
      Is_Enabled  : Boolean;
   end record;

   procedure Initialize_Syscall_Msrs
     (Handler_Addr : in     Unsigned_64;
      Passport     :    out Msr_Syscall_Passport;
      Success      :    out Boolean)
   with
     Global => null,
     Pre    => Handler_Addr /= 0,
     Post   => (if Success then Passport.Is_Enabled = True and Passport.Lstar_Value = Handler_Addr);

end Schild_Msr_Syscall_Core;
