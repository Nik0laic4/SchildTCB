with Interfaces; use Interfaces;
with Schild_Aes_Cbc_Engine;

package Schild_Crypto_Fabric with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   type Fabric_State_Type is (Uninitialized, Key_Ready, Context_Active, Faulted);

   type Fabric_Control_Record is record
      State       : Fabric_State_Type := Uninitialized;
      Cbc_Context : Schild_Aes_Cbc_Engine.Crypto_Context_Record;
   end record;

   procedure Initialize_Fabric_session
     (Control : in out Fabric_Control_Record;
      Success :    out Boolean)
   with Post => (if Success then Control.State = Key_Ready and Control.Cbc_Context.Is_Ready);

   procedure Process_Secure_Block
     (Control    : in out Fabric_Control_Record;
      Input_Data : in     Schild_Aes_Cbc_Engine.Cbc_Block_Buffer;
      Output_Data:    out Schild_Aes_Cbc_Engine.Cbc_Block_Buffer;
      Success    :    out Boolean)
   with Pre  => (Control.State = Key_Ready or Control.State = Context_Active) 
                and Control.Cbc_Context.Is_Ready, --  Processing needs ready key material and an armed CBC context.
        Post => (if Success then Control.State = Context_Active);

end Schild_Crypto_Fabric;
