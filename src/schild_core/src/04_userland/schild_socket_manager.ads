with Interfaces; use Interfaces;

package Schild_Socket_Manager with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   type Socket_Id_Type is new Interfaces.Unsigned_32 range 1 .. 4096;
   type Application_Port_Type is new Interfaces.Unsigned_16 range 1 .. 65535;

   type Socket_Descriptor_Record is record
      Socket_Id  : Socket_Id_Type := 1;
      Bound_Port : Application_Port_Type := 1;
      Owner_PID  : Interfaces.Unsigned_32 := 0;
      Is_Active  : Boolean := False;
   end record;

   procedure Assign_Socket_Port
     (Descriptor : in out Socket_Descriptor_Record;
      Port       : in     Application_Port_Type;
      PID        : in     Interfaces.Unsigned_32;
      Success    :    out Boolean)
   with Pre => PID > 1 and not Descriptor.Is_Active,
        Post => (if Success then Descriptor.Is_Active and Descriptor.Bound_Port = Port);

end Schild_Socket_Manager;
