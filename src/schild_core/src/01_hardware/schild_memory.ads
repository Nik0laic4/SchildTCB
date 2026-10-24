package Schild_Memory with SPARK_Mode is

   Max_Frames : constant := 1024;
   type Frame_Index is range 1 .. Max_Frames;
   
   type Frame_State is (Frame_Free, Frame_Allocated);

   type Page_Table_Type is array (Frame_Index) of Frame_State;

   type Memory_Manager is record
      Page_Table : Page_Table_Type := (others => Frame_Free);
      Free_Count : Integer range 0 .. Max_Frames := Max_Frames;
   end record;

   procedure Allocate_Page
     (Manager : in out Memory_Manager;
      Frame   :        Frame_Index)
   with
     Pre  => Manager.Free_Count > 0 and then
             Manager.Page_Table (Frame) = Frame_Free,
     Post => Manager.Free_Count = Manager.Free_Count'Old - 1 and then
             Manager.Page_Table (Frame) = Frame_Allocated;

end Schild_Memory;
