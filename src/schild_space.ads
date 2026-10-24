package Schild_Space with SPARK_Mode is

   --  256 address spaces.
   Max_ASID : constant := 256;
   type ASID_Index is range 1 .. Max_ASID;

   type Space_Status is (Space_Free, Space_Active);
   type ASID_Pool_Type is array (ASID_Index) of Space_Status;

   --  Tracks ASID allocation.
   type Space_Manager is record
      ASID_Pool     : ASID_Pool_Type := (others => Space_Free);
      Active_Spaces : Integer range 0 .. Max_ASID := 0;
   end record;

   --  Allocate an ASID.
   procedure Allocate_Space
     (Manager : in out Space_Manager;
      ASID    :        ASID_Index)
   with
     Pre  => Manager.Active_Spaces < Max_ASID and then
             Manager.ASID_Pool (ASID) = Space_Free,
     Post => Manager.Active_Spaces = Manager.Active_Spaces'Old + 1 and then
             Manager.ASID_Pool (ASID) = Space_Active;

end Schild_Space;
