package body Schild_User_Memory with
  SPARK_Mode => Off --  Scaffold: user heap allocation always reports success.
is

   procedure Allocate_User_Heap
     (Requested_Addr : in     User_Virtual_Address;
      Size_Bytes     : in     Interfaces.Unsigned_64;
      Status         :    out Allocation_Status)
   is
   begin
      --  Scaffold: no actual heap is reserved.
      Status := Alloc_Success;
   end Allocate_User_Heap;

end Schild_User_Memory;
