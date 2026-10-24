package body Schild_Memory with SPARK_Mode is

   procedure Allocate_Page (Manager : in out Memory_Manager; Frame : Frame_Index) is
   begin
      --  Mark the frame allocated.
      Manager.Page_Table (Frame) := Frame_Allocated;
      
      --  Decrement the free counter.
      Manager.Free_Count         := Manager.Free_Count - 1;
   end Allocate_Page;

end Schild_Memory;
