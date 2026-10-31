--  Schild TCB - capability space model.
--  Capability kinds, rights, the derivation table and mint/copy/retype/revoke.

with Interfaces;

package Schild_Cap_Space with
  SPARK_Mode => On
is
   pragma Elaborate_Body;
   use Interfaces;

   type Cap_Type is
     (Cap_Null, Cap_TCB, Cap_CNode, Cap_VSpace, Cap_IPC_Buffer,
      Cap_Untyped, Cap_Frame, Cap_PageTable, Cap_PageDir,
      Cap_ASID_Pool, Cap_IRQ_Control, Cap_IRQ_Handler,
      Cap_Endpoint, Cap_Notification, Cap_Domain);

   subtype Physical_Cap is Cap_Type range Cap_Untyped .. Cap_Frame;
   subtype Kernel_Cap   is Cap_Type range Cap_TCB     .. Cap_IPC_Buffer;

   type Cap_Rights is mod 2**8;
   Right_None  : constant Cap_Rights := 0;
   Right_Read  : constant Cap_Rights := 1;
   Right_Write : constant Cap_Rights := 2;
   Right_Grant : constant Cap_Rights := 4;
   Right_All   : constant Cap_Rights := Right_Read or Right_Write or Right_Grant;

   type Cap_Id    is mod 2**64;
   Max_Cap_Slots : constant := 64;
   type Cap_Index is range 0 .. Max_Cap_Slots - 1;
   type Cap_Depth is range 0 .. 32;
   type Badge_Value is mod 2**64;

   Null_Cap_Id : constant Cap_Id := 0;

   --  A Parent reference is either the null capability or a table index.
   --  Narrowing the type (0 .. Max_Cap_Slots-1) makes every `Cap_Index (Parent)`
   --  conversion provably in-range (no erasure of the bound in `Cap_Id`).
   subtype Parent_Id is Cap_Id range 0 .. Cap_Id (Max_Cap_Slots - 1);

   type Cap_Node is record
      The_Kind    : Cap_Type     := Cap_Null;
      Rights      : Cap_Rights   := Right_None;
      Parent      : Parent_Id    := Null_Cap_Id;
      Badge       : Badge_Value  := 0;
      Depth       : Cap_Depth    := 0;
      Phys_Addr   : Unsigned_64  := 0;
      Size_Bits   : Unsigned_32  := 0;
   end record;

   Null_Node : constant Cap_Node :=
     (The_Kind => Cap_Null, Rights => Right_None,
      Parent => Null_Cap_Id, Badge => 0, Depth => 0,
      Phys_Addr => 0, Size_Bits => 0);

   type Cap_Table is array (Cap_Index) of Cap_Node;
   Init_Table : constant Cap_Table := (others => Null_Node);

   procedure Cap_Mint
     (Table    : in out Cap_Table;
      Src      : in     Cap_Index;
      Dest     : in     Cap_Index;
      New_Right: in     Cap_Rights;
      Badge    : in     Badge_Value;
      Success  :    out Boolean)
   with
     Pre  => Src /= Dest,
     Post => (if Success then
                Table (Dest).The_Kind = Table'Old (Src).The_Kind
                  and Table (Dest).Parent = Cap_Id (Src)
                  and Table (Dest).Badge = Badge
                  and Table (Dest).Rights = (Table'Old (Src).Rights and New_Right)
                  and Table (Dest).Rights <= Table'Old (Src).Rights);

   procedure Cap_Revoke
     (Table    : in out Cap_Table;
      Slot     : in     Cap_Index)
   with
     Post => Table (Slot) = Null_Node;

   procedure Cap_Delete
     (Table    : in out Cap_Table;
      Slot     : in     Cap_Index)
   with
     Post => Table (Slot) = Null_Node;

   procedure Cap_Copy
     (Table    : in out Cap_Table;
      Src      : in     Cap_Index;
      Dest     : in     Cap_Index;
      Success  :    out Boolean)
   with
     Pre  => Src /= Dest,
     Post => (if Success then Table (Dest) = Table'Old (Src));

   procedure Cap_Retype
     (Table      : in out Cap_Table;
      Untyped    : in     Cap_Index;
      New_Type   : in     Cap_Type;
      Size_Bits  : in     Unsigned_32;
      New_Slot   : in     Cap_Index;
      Success    :    out Boolean)
   with
     Pre  => Untyped < Max_Cap_Slots
              and New_Slot < Max_Cap_Slots
              and Untyped /= New_Slot
              and Table (Untyped).The_Kind = Cap_Untyped
              and New_Type in Physical_Cap,
     Post => (if Success then
                Table (New_Slot).The_Kind = New_Type
                  and Table (New_Slot).Rights = Right_All
                  and Table (New_Slot).Parent = Cap_Id (Untyped)
                  and Table (New_Slot).Depth = 0
                  and Table (New_Slot).Phys_Addr = Table'Old (Untyped).Phys_Addr
                  and Table (New_Slot).Size_Bits = Size_Bits
                  and Table (Untyped).The_Kind = Cap_Null);

   function Is_Null  (Node : Cap_Node) return Boolean is (Node.The_Kind = Cap_Null);
   function Is_Valid (Node : Cap_Node) return Boolean is (Node.The_Kind /= Cap_Null);
   function Has_Right (Node : Cap_Node; R : Cap_Rights) return Boolean is
     ((Node.Rights and R) = R);
   function Is_Derived_From (Table : Cap_Table; Child, Ancestor : Cap_Index) return Boolean;

end Schild_Cap_Space;
