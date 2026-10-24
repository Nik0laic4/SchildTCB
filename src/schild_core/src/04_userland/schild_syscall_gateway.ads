pragma Spark_Mode (On);

package Schild_Syscall_Gateway is

   type Syscall_ID_Type is mod 2**64;

   --  Valid syscall-id range enforced by the gateway.
   MIN_SYSCALL_ID : constant Syscall_ID_Type := 1;
   MAX_SYSCALL_ID : constant Syscall_ID_Type := 10;

   --  True when the id falls inside the allowed range.
   function Is_Valid_Syscall_ID (ID : Syscall_ID_Type) return Boolean
   with
     Global => null,
     Post   => Is_Valid_Syscall_ID'Result = (ID >= MIN_SYSCALL_ID and ID <= MAX_SYSCALL_ID);

end Schild_Syscall_Gateway;
