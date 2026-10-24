-- Schild TCB — observability abstraction for SPARK-proven modules.
--
-- Logging is an *observational* side effect: it must not mutate any
-- security-relevant state. The `Global => null` contract states this promise,
-- which is what lets tier-A modules (MLS, capability model, process table)
-- log without poisoning SPARK flow analysis.
--
-- The body is `SPARK_Mode => Off` and forwards to the platform UART driver
-- (asm + C import). This is a deliberate, trusted abstraction: the human
-- asserts the contract; the platform does the I/O.

package Schild_Log with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   --  Append Text to the boot log (no trailing newline).
   procedure Put_String (Text : String) with
     Global => null;

   --  Append Text to the boot log followed by CR+LF.
   procedure Put_Line (Text : String) with
     Global => null;
end Schild_Log;
