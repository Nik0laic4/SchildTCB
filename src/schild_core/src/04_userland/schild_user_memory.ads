with Interfaces; use Interfaces;

package Schild_User_Memory with
  SPARK_Mode => On
is

   type User_Virtual_Address is new Interfaces.Unsigned_64;
   type Allocation_Status is (Alloc_Success, Alloc_Out_Of_Memory, Alloc_Denied);

   User_Space_Limit : constant User_Virtual_Address := 16#0000_7FFF_FFFF_F000#;

   procedure Allocate_User_Heap
     (Requested_Addr : in     User_Virtual_Address;
      Size_Bytes     : in     Interfaces.Unsigned_64;
      Status         :    out Allocation_Status)
   with Pre => Requested_Addr < User_Space_Limit,
        Post => (if Status = Alloc_Success then Requested_Addr + User_Virtual_Address (Size_Bytes) <= User_Space_Limit);

end Schild_User_Memory;
