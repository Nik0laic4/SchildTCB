pragma Spark_Mode (On);

package Schild_Pcie_Cap_Parser is

   type Cap_Ptr_Type is mod 2**8;
   type Iteration_Counter is range 0 .. 48;

   --  Upper bound on capability-list traversal steps (guards cycles).
   MAX_CAP_ITERATIONS : constant Iteration_Counter := 32;

   --  Accept a walk step only while under the limit and moving to a new pointer.
   procedure Validate_Cap_Step
     (Current_Ptr : in     Cap_Ptr_Type;
      Next_Ptr    : in     Cap_Ptr_Type;
      Iterations  : in     Iteration_Counter;
      Is_Parse_Safe :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Parse_Safe => (Current_Ptr, Next_Ptr, Iterations)),
     Post    => Is_Parse_Safe = (Iterations < MAX_CAP_ITERATIONS and then 
                                 Next_Ptr /= Current_Ptr and then
                                 Next_Ptr /= 0);

end Schild_Pcie_Cap_Parser;
