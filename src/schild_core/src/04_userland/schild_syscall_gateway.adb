pragma Spark_Mode (On);

package body Schild_Syscall_Gateway is

   function Is_Valid_Syscall_ID (ID : Syscall_ID_Type) return Boolean is
   begin
      return (ID >= MIN_SYSCALL_ID and ID <= MAX_SYSCALL_ID);
   end Is_Valid_Syscall_ID;

end Schild_Syscall_Gateway;
