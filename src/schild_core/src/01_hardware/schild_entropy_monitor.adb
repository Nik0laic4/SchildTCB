pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Entropy_Monitor is

   procedure Audit_Entropy_Stream
     (New_Value : in     Unsigned_64;
      Monitor   : in out Entropy_Monitor_Record;
      Is_Trusted :    out Boolean)
   is
   begin
      --  Fresh entropy differs from the last sample.
      if New_Value /= Monitor.Last_Value then
         Monitor.Last_Value := New_Value;
         Is_Trusted         := True;
      else
         Is_Trusted         := False;
      end if;
   end Audit_Entropy_Stream;

end Schild_Entropy_Monitor;
