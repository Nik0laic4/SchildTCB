pragma Spark_Mode (On);

package Schild_Audit_Hooks is

   function Is_Buffer_Ready return Boolean;
   
   procedure Log_Syscall_Violation;

end Schild_Audit_Hooks;
