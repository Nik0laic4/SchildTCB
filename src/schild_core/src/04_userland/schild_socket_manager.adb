package body Schild_Socket_Manager with
  SPARK_Mode => On --  Privileged-port policy: only PID 2 may bind ports < 1024.
is

   procedure Assign_Socket_Port
     (Descriptor : in out Socket_Descriptor_Record;
      Port       : in     Application_Port_Type;
      PID        : in     Interfaces.Unsigned_32;
      Success    :    out Boolean)
   is
   begin
      --  Reject binding of privileged ports by unprivileged processes.
      if Port < 1024 and PID /= 2 then
         --  Bind denied.
         Success := False;
      else
         Descriptor.Bound_Port := Port;
         Descriptor.Owner_PID  := PID;
         Descriptor.Is_Active  := True;
         Success               := True;
      end if;
   end Assign_Socket_Port;

end Schild_Socket_Manager;
