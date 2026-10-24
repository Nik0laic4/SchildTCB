pragma Spark_Mode (On);

package body Schild_Msr_Syscall_Core is

   procedure Initialize_Syscall_Msrs
     (Handler_Addr : in     Interfaces.Unsigned_64;
      Passport     :    out Msr_Syscall_Passport;
      Success      :    out Boolean)
   is
   begin
      if Handler_Addr /= 0 then
         --  Program the STAR MSR with the syscall selectors.
         Passport.Star_Value  := 16#001B_0008_0000_0000#;
         Passport.Lstar_Value := Handler_Addr;
         Passport.Is_Enabled  := True;
         Success              := True;
      else
         Passport   := (Star_Value => 0, Lstar_Value => 0, Is_Enabled => False);
         Success    := False;
      end if;
   end Initialize_Syscall_Msrs;

end Schild_Msr_Syscall_Core;
