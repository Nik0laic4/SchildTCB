package body Schild_Cap_Space with
  SPARK_Mode => On
is

   procedure Cap_Mint
     (Table    : in out Cap_Table;
      Src      : in     Cap_Index;
      Dest     : in     Cap_Index;
      New_Right: in     Cap_Rights;
      Badge    : in     Badge_Value;
      Success  :    out Boolean)
   is
   begin
      if Is_Null (Table (Src)) then
         Success := False;
         return;
      end if;
      Table (Dest) := Table (Src);
      Table (Dest).Rights := Table (Src).Rights and New_Right;
      Table (Dest).Parent := Cap_Id (Src);
      Table (Dest).Badge  := Badge;
      --  Clamp depth at Cap_Depth'Last so the +1 can never overflow.
      if Table (Src).Depth < Cap_Depth'Last then
         Table (Dest).Depth := Table (Src).Depth + 1;
      else
         Table (Dest).Depth := Cap_Depth'Last;
      end if;
      Success := True;
   end Cap_Mint;

   procedure Cap_Copy
     (Table    : in out Cap_Table;
      Src      : in     Cap_Index;
      Dest     : in     Cap_Index;
      Success  :    out Boolean)
   is
   begin
      if Is_Null (Table (Src)) then
         Success := False;
         return;
      end if;
      Table (Dest) := Table (Src);
      Success := True;
   end Cap_Copy;

   procedure Cap_Revoke
     (Table    : in out Cap_Table;
      Slot     : in     Cap_Index)
   is
   begin
      --  Revoke the target slot directly (satisfies the postcondition), then
      --  iteratively null every slot whose parent is already revoked. A
      --  derivation chain is at most Cap_Depth'Last long, so Cap_Depth passes
      --  suffice; each pass is a bounded for-loop (SPARK-provable, no stack).
      Table (Slot) := Null_Node;

      for Pass in Cap_Depth loop
         pragma Loop_Invariant (Table (Slot) = Null_Node);
         for I in Cap_Index loop
            pragma Loop_Invariant (Table (Slot) = Null_Node);
            if Table (I).The_Kind /= Cap_Null
              and then Table (I).Parent /= Null_Cap_Id
              and then Table (Cap_Index (Table (I).Parent)).The_Kind = Cap_Null
            then
               Table (I) := Null_Node;
            end if;
         end loop;
      end loop;
   end Cap_Revoke;

   procedure Cap_Delete
     (Table    : in out Cap_Table;
      Slot     : in     Cap_Index)
   is
   begin
      Table (Slot) := Null_Node;
   end Cap_Delete;

   procedure Cap_Retype
     (Table      : in out Cap_Table;
      Untyped    : in     Cap_Index;
      New_Type   : in     Cap_Type;
      Size_Bits  : in     Unsigned_32;
      New_Slot   : in     Cap_Index;
      Success    :    out Boolean)
   is
   begin
      if Table (Untyped).The_Kind /= Cap_Untyped then
         Success := False;
         return;
      end if;
      if not (New_Type in Physical_Cap) then
         Success := False;
         return;
      end if;
      Table (New_Slot) := Null_Node;
      Table (New_Slot).The_Kind  := New_Type;
      Table (New_Slot).Rights    := Right_All;
      Table (New_Slot).Phys_Addr := Table (Untyped).Phys_Addr;
      Table (New_Slot).Size_Bits := Size_Bits;
      Table (New_Slot).Parent    := Cap_Id (Untyped);
      Table (New_Slot).Depth     := 0;
      Table (Untyped) := Null_Node;
      Success := True;
   end Cap_Retype;

   function Is_Derived_From
     (Table : Cap_Table; Child, Ancestor : Cap_Index) return Boolean
   is
      Target  : constant Cap_Id := Cap_Id (Ancestor);
      Current : Parent_Id := Table (Child).Parent;
   begin
      -- Direct parent (basis for the spec post): checked before the loop so
      -- the postcondition discharges without loop reasoning.
      if Current = Target then
         return True;
      end if;
      -- Walk ancestors up to Cap_Depth'Last steps; stop at the null cap.
      for I in Cap_Depth loop
         if Current = Null_Cap_Id then
            return False;
         end if;
         Current := Table (Cap_Index (Current)).Parent;
         if Current = Target then
            return True;
         end if;
      end loop;
      return False;
   end Is_Derived_From;

end Schild_Cap_Space;
