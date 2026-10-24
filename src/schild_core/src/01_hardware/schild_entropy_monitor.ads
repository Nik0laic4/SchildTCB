pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_64 for the entropy value.

package Schild_Entropy_Monitor is

   type Entropy_Monitor_Record is record
      Last_Value : Unsigned_64;
   end record;

   procedure Audit_Entropy_Stream
     (New_Value : in     Unsigned_64;
      Monitor   : in out Entropy_Monitor_Record;
      Is_Trusted :    out Boolean)
   with
     Global => null,
     Post   => (if New_Value = Monitor.Last_Value'Old then not Is_Trusted);

end Schild_Entropy_Monitor;
