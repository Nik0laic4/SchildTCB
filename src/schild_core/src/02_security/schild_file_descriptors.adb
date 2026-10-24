--  Schild TCB - file descriptor table body.
--  Scaffold: streams write to the UART; reads from stdin return 0; access
--  control enforces Bell-LaPadula (read up forbidden, write down forbidden).

with Schild_Uart_Driver;

with Interfaces;

package body Schild_File_Descriptors with
  SPARK_Mode => On
is
   use type Interfaces.Unsigned_32;

   ---------------
   -- Open_Descriptor --
   ---------------
   procedure Open_Descriptor
     (Table   : in out Descriptor_Table;
      Cap     : in     Cap_Id;
      Stream  : in     Stream_Type;
      Level   : in     Interfaces.Unsigned_32;
      Fd      :    out Descriptor_Id;
      Status  :    out Fd_Status)
   is
   begin
      Fd := 0;
      Status := Table_Full;

      --  Claim the first free slot for the new descriptor.
      for I in Table'Range loop
         if not Table (I).Is_Open then
            Table (I).Id        := Descriptor_Id (I);
            Table (I).Stream    := Stream;
            Table (I).Owner_Cap := Cap;
            Table (I).Mls_Level := Level;
            Table (I).Is_Open   := True;
            Fd     := Table (I).Id;
            Status := Success;
            Schild_Uart_Driver.Put_Line ("FD: opened descriptor");
            exit;
         end if;
      end loop;
   end Open_Descriptor;

   -----------------
   -- Close_Descriptor --
   -----------------
   procedure Close_Descriptor
     (Table  : in out Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Status :    out Fd_Status)
   is
   begin
      Status := Invalid_Fd;

      for I in Table'Range loop
         if Table (I).Is_Open and then Table (I).Id = Fd then
            Table (I).Is_Open := False;
            Status := Success;
            Schild_Uart_Driver.Put_Line ("FD: closed descriptor");
            exit;
         end if;
      end loop;
   end Close_Descriptor;

   ---------------
   -- Write_Byte --
   ---------------
   procedure Write_Byte
     (Table  : in     Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Byte   : in     Interfaces.Unsigned_8;
      Status :    out Fd_Status)
   is
   begin
      Status := Invalid_Fd;

      for I in Table'Range loop
         if Table (I).Is_Open and then Table (I).Id = Fd then
            if Table (I).Stream = Stdout or else Table (I).Stream = Stderr then
               Schild_Uart_Driver.Put_Char (Character'Val (Integer (Byte)));
               Status := Success;
            else
               Status := Access_Denied;
            end if;
            exit;
         end if;
      end loop;
   end Write_Byte;

   ----------------
   -- Read_Byte  --
   ----------------
   procedure Read_Byte
     (Table  : in     Descriptor_Table;
      Fd     : in     Descriptor_Id;
      Byte   :    out Interfaces.Unsigned_8;
      Status :    out Fd_Status)
   is
   begin
      Byte := 0;
      Status := Invalid_Fd;

      for I in Table'Range loop
         if Table (I).Is_Open and then Table (I).Id = Fd then
            if Table (I).Stream = Stdin then
               --  Scaffold: stdin always returns a NUL byte.
               Byte := 0;
               Status := Success;
            else
               Status := Access_Denied;
            end if;
            exit;
         end if;
      end loop;
   end Read_Byte;

   -----------------
   -- Check_Access --
   -----------------
   function Check_Access
     (Table    : Descriptor_Table;
      Fd       : Descriptor_Id;
      Proc_Level : Interfaces.Unsigned_32;
      Is_Read  : Boolean) return Boolean
   is
   begin
      for I in Table'Range loop
         if Table (I).Is_Open and then Table (I).Id = Fd then
            --  Bell-LaPadula: read needs dominance (>=), write needs (<=).
            if Is_Read then
               return Proc_Level >= Table (I).Mls_Level;
            else
               return Proc_Level <= Table (I).Mls_Level;
            end if;
         end if;
      end loop;
      return False;
   end Check_Access;

   ----------------------------
   -- Init_Descriptor_Table  --
   ----------------------------
   procedure Init_Descriptor_Table
     (Table      : out Descriptor_Table;
      Owner_Cap  : in  Cap_Id)
   is
   begin
      Table := [others => File_Descriptor'(Id => 0, Stream => Stdin,
                Owner_Cap => Owner_Cap, Mls_Level => 1, Is_Open => False)];
      Schild_Uart_Driver.Put_Line ("FD: descriptor table initialized");
   end Init_Descriptor_Table;

   -----------------------------
   -- Init_Standard_Streams   --
   -----------------------------
   procedure Init_Standard_Streams
     (Table : in out Descriptor_Table)
   is
      Fd      : Descriptor_Id;
      Status  : Fd_Status;
   begin
      -- stdid: fd 0
      Open_Descriptor (Table, Null_Cap, Stdin,  1, Fd, Status);
      -- stdout: fd 1
      Open_Descriptor (Table, Null_Cap, Stdout, 1, Fd, Status);
      -- stderr: fd 2
      Open_Descriptor (Table, Null_Cap, Stderr, 1, Fd, Status);
      Schild_Uart_Driver.Put_Line ("FD: standard streams initialized (stdin/stdout/stderr)");
   end Init_Standard_Streams;

end Schild_File_Descriptors;