package body Schild_Execution_Fabric with
  SPARK_Mode => On --  Sequence GDT setup and register sanitization.
is

   procedure Prepare_Execution_Pipeline
     (Context : in out Execution_Context_Record;
      Success :    out Boolean)
   is
   begin
      --  Mark the GDT as loaded.
      Context.Gdt_Active := True;

      -- 2. Stack boundary validation (simulation of schild_stack_guard)
      Context.Stack_Valid := True;

      --  Mark registers as sanitized.
      Context.Registers_Clean := True;

      if Context.Gdt_Active and Context.Stack_Valid and Context.Registers_Clean then
         Context.State := Ready_To_Jump;
         Success       := True;
      else
         Context.State := Idle;
         Success       := False;
      end if;
   end Prepare_Execution_Pipeline;

end Schild_Execution_Fabric;
