pragma Spark_Mode (On);

package body Schild_Audit_Hooks is

   function Is_Buffer_Ready return Boolean is
   begin
      return True;
   end Is_Buffer_Ready;

   procedure Log_Syscall_Violation is
   begin
      null;
   end Log_Syscall_Violation;

end Schild_Audit_Hooks;
