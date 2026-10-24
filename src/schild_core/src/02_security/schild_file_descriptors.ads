--  Schild TCB - file descriptor table.
--  A per-process table of open streams (stdin/stdout/stderr/pipe/file), each
--  bound to a capability and an MLS level for access control.

with Interfaces;
with Schild_Sel4_Ipc;

package Schild_File_Descriptors with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   use Schild_Sel4_Ipc;

   --  Kind of open stream.
   type Stream_Type is (Stdin, Stdout, Stderr, Pipe, File);

   --  Opaque descriptor handle (0 is invalid).
   type Descriptor_Id is mod 2**32;
   type File_Descriptor is record
      Id          : Descriptor_Id := 0;
      Stream      : Stream_Type := Stdin;
      Owner_Cap   : Cap_Id := Null_Cap;  --  Capability backing this stream.
      Mls_Level   : Interfaces.Unsigned_32 := 1;  -- Public
      Is_Open     : Boolean := False;
   end record;

   --  Fixed-size descriptor table.
   Max_Descriptors : constant := 16;
   type Descriptor_Table is array (1 .. Max_Descriptors) of File_Descriptor;

   --  Result of a descriptor operation.
   type Fd_Status is (Success, Invalid_Fd, Access_Denied, Table_Full);

   ------------------------------------------------------------
   --  Descriptor operations.
   ------------------------------------------------------------

   --  Open a new descriptor for the given capability and stream type.
   procedure Open_Descriptor
     (Table   : in out Descriptor_Table;
      Cap     : in     Cap_Id;
      Stream  : in     Stream_Type;
      Level   : in     Interfaces.Unsigned_32;
      Fd      :    out Descriptor_Id;
      Status  :    out Fd_Status);

   --  Close a descriptor and release its slot.
   procedure Close_Descriptor
     (Table  : in out Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Status :    out Fd_Status);

   --  Write one byte through a descriptor.
   procedure Write_Byte
     (Table  : in     Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Byte   : in     Interfaces.Unsigned_8;
      Status :    out Fd_Status)
   with
     Pre => Fd /= 0;

   --  Read one byte from a descriptor.
   procedure Read_Byte
     (Table  : in     Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Byte   :    out Interfaces.Unsigned_8;
      Status :    out Fd_Status)
   with
     Pre => Fd /= 0;

   --  True when a process at Proc_Level may read/write this descriptor.
   function Check_Access
     (Table    : Descriptor_Table;
      Fd       : Descriptor_Id;
      Proc_Level : Interfaces.Unsigned_32;
      Is_Read  : Boolean) return Boolean;

   --  Reset the descriptor table with a given owner capability.
   procedure Init_Descriptor_Table
     (Table      : out Descriptor_Table;
      Owner_Cap  : in  Cap_Id);

   --  Install stdin/stdout/stderr in a fresh table.
   procedure Init_Standard_Streams
     (Table : in out Descriptor_Table);

end Schild_File_Descriptors;