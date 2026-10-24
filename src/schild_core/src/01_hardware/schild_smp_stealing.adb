package body Schild_Smp_Stealing with
  SPARK_Mode => On --  Work-stealing scaffold.
is

   procedure Execute_Work_Stealing
     (Passport : in out Steal_Passport_Record;
      Success  :    out Boolean)
   is
   begin
      --  Not implemented: real work-stealing requires an atomic dequeue from
      --  the victim run-queue. Report honestly.
      Passport.Tasks_Stolen := 0;
      Success               := False;
   end Execute_Work_Stealing;

end Schild_Smp_Stealing;
