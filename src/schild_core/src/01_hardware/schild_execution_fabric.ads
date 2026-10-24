with Interfaces; use Interfaces;

package Schild_Execution_Fabric with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Execution_State_Type is (Idle, Context_Loaded, Sanitized, Ready_To_Jump);

   type Execution_Context_Record is record
      State           : Execution_State_Type := Idle;
      Gdt_Active      : Boolean := False;
      Stack_Valid     : Boolean := False;
      Registers_Clean : Boolean := False;
   end record;

   procedure Prepare_Execution_Pipeline
     (Context : in out Execution_Context_Record;
      Success :    out Boolean)
   with Post => (if Success then Context.State = Ready_To_Jump 
                 and Context.Gdt_Active 
                 and Context.Registers_Clean);
   --  Success requires a loaded GDT and clean registers.

end Schild_Execution_Fabric;
