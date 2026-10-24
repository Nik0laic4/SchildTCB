with System.Machine_Code; use System.Machine_Code;

package body Schild_Smp_Time with
  SPARK_Mode => Off --  Per-core timestamp scaffold.
is

   procedure Synchronize_Core_Tsc
     (Time_Card : in out Core_Time_Record;
      Max_Drift : in     Tsc_Tick_Count;
      Success   :    out Boolean)
   is
   begin
      -- Architectural cross-core sync barrier time bus
      System.Machine_Code.Asm (Template => "mfence", Volatile => True);
      Time_Card.Status := Sync_Ideal;
      Success := True;
   end Synchronize_Core_Tsc;

end Schild_Smp_Time;
