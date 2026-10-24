pragma Spark_Mode (On);

package body Schild_Pcie_Cap_Parser is

   procedure Validate_Cap_Step
     (Current_Ptr : in     Cap_Ptr_Type;
      Next_Ptr    : in     Cap_Ptr_Type;
      Iterations  : in     Iteration_Counter;
      Is_Parse_Safe :    out Boolean)
   is
   begin
      --  Safe while under the iteration cap and advancing to a new pointer.
      Is_Parse_Safe := (Iterations < MAX_CAP_ITERATIONS and then 
                        Next_Ptr /= Current_Ptr and then
                        Next_Ptr /= 0);
   end Validate_Cap_Step;

end Schild_Pcie_Cap_Parser;
