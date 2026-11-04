-- Schild TCB — FS Daemon (Ring 3) body.
-- Audit H65: thin wrapper over Schild_Schild_Fs. Handles are Start_LBA values
-- (unique per file within one mount). Large data via shared frame @ 0x520000.
with System;
with Interfaces; use Interfaces;
with Schild_Schild_Fs;
with Schild_Nvme;

package body Schild_Fs_Server with SPARK_Mode => Off is

   procedure Shared_Copy_From (Dst : System.Address; Len : Unsigned_32);
   pragma Import (C, Shared_Copy_From, "schild_shared_copy_from");
   procedure Shared_Copy_To (Src : System.Address; Len : Unsigned_32);
   pragma Import (C, Shared_Copy_To, "schild_shared_copy_to");

   function C_Nvme_Get_Mmio return Unsigned_64;
   pragma Import (C, C_Nvme_Get_Mmio, "schild_nvme_get_mmio");

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   Initialized : Boolean := False;

   function Fs_Init return Unsigned_32 is
      MMIO_Base : Unsigned_64;
      Ok        : Boolean;
      Msg_Mount : constant String := "[NVFS] Init OK";
      Msg_Ready : constant String := "[NVFS] test.txt ready";
      Msg_Write : constant String := "[NVFS] Write OK";
      Msg_Read  : constant String := "[NVFS] Read-back VERIFY OK";
   begin
      MMIO_Base := C_Nvme_Get_Mmio;
      if MMIO_Base = 0 then
         return St_Io_Error;
      end if;
      Schild_Nvme.Init_MMIO (MMIO_Base);
      Schild_Schild_Fs.Init (Ok);
      if not Ok then
         return St_Not_Mounted;
      end if;
      C_Putln (Msg_Mount'Address, Msg_Mount'Length);

      -- Audit H86: the storage self-test moved here from NetServer, because
      -- this daemon is now the single NVMe owner.  The run_tests markers must
      -- describe what the owner did, not what the former owner used to do.
      declare
         F    : Schild_Schild_Fs.File_Info;
         Buf  : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31);
         Len  : Unsigned_32;
         Data : constant Schild_Schild_Fs.Unsigned_8_Array (0 .. 511) :=
           (0=>78,1=>101,2=>118,3=>97,4=>79,5=>83,
            6=>32,7=>119,8=>114,9=>105,10=>116,11=>101,
            12=>115,13=>116,14=>33,15=>10, others=> 0);
      begin
         -- Audit H77: open first, create only if missing.
         Schild_Schild_Fs.Open ("test.txt", F, Ok);
         if not Ok then
            Schild_Schild_Fs.Create_File ("test.txt", 512, Ok);
         end if;
         if Ok then
            C_Putln (Msg_Ready'Address, Msg_Ready'Length);
            Schild_Schild_Fs.Open ("test.txt", F, Ok);
            if Ok then
               Schild_Schild_Fs.Write_File (F, Data, Ok);
               if Ok then
                  C_Putln (Msg_Write'Address, Msg_Write'Length);
                  F.Curr_Off := 0;
                  Schild_Schild_Fs.Read (F, Buf, Len, Ok);
                  if Ok and then Len >= 2
                    and then Buf (0) = 78 and then Buf (1) = 101
                  then
                     C_Putln (Msg_Read'Address, Msg_Read'Length);
                  end if;
               end if;
            end if;
         end if;
      end;

      Initialized := True;
      return St_Ok;
   end Fs_Init;

   function Find_By_Start_LBA
     (Handle : Unsigned_32; F : out Schild_Schild_Fs.File_Info) return Boolean
   is
      Ent  : Schild_Schild_Fs.Dir_Entry;
      Ok   : Boolean;
      Idx  : Unsigned_32 := 0;
   begin
      loop
         Schild_Schild_Fs.Get_Entry (Idx, Ent, Ok);
         exit when not Ok;
         if Ent.Start_LBA = Handle then
            F.Valid     := True;
            F.Name      := Ent.Name;
            F.Start_LBA := Ent.Start_LBA;
            F.Size      := Ent.Size;
            F.Curr_Off  := 0;
            return True;
         end if;
         Idx := Idx + 1;
      end loop;
      return False;
   end Find_By_Start_LBA;

   function Fs_Open
     (Name_Len : Unsigned_32;
      Handle   : out Unsigned_32;
      Size     : out Unsigned_32) return Unsigned_32
   is
      Name_Buf : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31) := (others => 0);
      Name_Str : String (1 .. 24) := (others => ' ');
      F        : Schild_Schild_Fs.File_Info;
      Ok       : Boolean;
      L        : constant Unsigned_32 := (if Name_Len > 24 then 24 else Name_Len);
   begin
      Handle := 0; Size := 0;
      if not Initialized then return St_Not_Mounted; end if;
      if L = 0 then return St_Bad_Op; end if;
      Shared_Copy_From (Name_Buf (0)'Address, L);
      for I in 0 .. Integer (L) - 1 loop
         Name_Str (I + 1) := Character'Val (Name_Buf (I));
      end loop;
      Schild_Schild_Fs.Open (Name_Str (1 .. Integer (L)), F, Ok);
      if not Ok then return St_No_File; end if;
      Handle := F.Start_LBA;
      Size   := F.Size;
      return St_Ok;
   end Fs_Open;

   function Fs_Read
     (Handle : Unsigned_32; Offset : Unsigned_32; Len : Unsigned_32;
      Actual : out Unsigned_32) return Unsigned_32
   is
      F     : Schild_Schild_Fs.File_Info;
      Buf   : Schild_Schild_Fs.Unsigned_8_Array (0 .. 2047);
      Got   : Unsigned_32;
      Ok    : Boolean;
      L     : constant Unsigned_32 := (if Len > 2048 then 2048 else Len);
   begin
      Actual := 0;
      if not Initialized then return St_Not_Mounted; end if;
      if not Find_By_Start_LBA (Handle, F) then return St_No_File; end if;
      F.Curr_Off := Offset;
      Schild_Schild_Fs.Read (F, Buf (0 .. Integer (L) - 1), Got, Ok);
      if not Ok then return St_Io_Error; end if;
      if Got > 0 then
         Shared_Copy_To (Buf (0)'Address, Got);
      end if;
      Actual := Got;
      return St_Ok;
   end Fs_Read;

   function Fs_Write
     (Handle : Unsigned_32; Offset : Unsigned_32; Len : Unsigned_32;
      New_Off : out Unsigned_32) return Unsigned_32
   is
      F     : Schild_Schild_Fs.File_Info;
      Buf   : Schild_Schild_Fs.Unsigned_8_Array (0 .. 2047);
      Ok    : Boolean;
      L     : constant Unsigned_32 := (if Len > 2048 then 2048 else Len);
   begin
      New_Off := Offset;
      if not Initialized then return St_Not_Mounted; end if;
      if Schild_Schild_Fs.Is_Read_Only then return St_Read_Only; end if;
      if not Find_By_Start_LBA (Handle, F) then return St_No_File; end if;
      Shared_Copy_From (Buf (0)'Address, L);
      F.Curr_Off := Offset;
      Schild_Schild_Fs.Write_File (F, Buf (0 .. Integer (L) - 1), Ok);
      if not Ok then return St_Io_Error; end if;
      New_Off := Offset + L;
      return St_Ok;
   end Fs_Write;

   function Fs_Create
     (Name_Len : Unsigned_32; Size : Unsigned_32;
      Handle   : out Unsigned_32) return Unsigned_32
   is
      Name_Buf : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31) := (others => 0);
      Name_Str : String (1 .. 24) := (others => ' ');
      Ok       : Boolean;
      F        : Schild_Schild_Fs.File_Info;
      L        : constant Unsigned_32 := (if Name_Len > 24 then 24 else Name_Len);
   begin
      Handle := 0;
      if not Initialized then return St_Not_Mounted; end if;
      if Schild_Schild_Fs.Is_Read_Only then return St_Read_Only; end if;
      if L = 0 then return St_Bad_Op; end if;
      Shared_Copy_From (Name_Buf (0)'Address, L);
      for I in 0 .. Integer (L) - 1 loop
         Name_Str (I + 1) := Character'Val (Name_Buf (I));
      end loop;
      Schild_Schild_Fs.Create_File (Name_Str (1 .. Integer (L)), Size, Ok);
      if not Ok then return St_No_Space; end if;
      Schild_Schild_Fs.Open (Name_Str (1 .. Integer (L)), F, Ok);
      if Ok then Handle := F.Start_LBA; end if;
      return St_Ok;
   end Fs_Create;

   function Fs_Append
     (Name_Len : Unsigned_32; Len : Unsigned_32;
      New_Size : out Unsigned_32) return Unsigned_32
   is
      pragma Unreferenced (Name_Len);
      Buf : Schild_Schild_Fs.Unsigned_8_Array (0 .. 4095) := (others => 0);
      F   : Schild_Schild_Fs.File_Info;
      Ok  : Boolean;
      L   : constant Unsigned_32 := (if Len > 4096 then 4096 else Len);
   begin
      New_Size := 0;
      if not Initialized then return St_Not_Mounted; end if;
      if Schild_Schild_Fs.Is_Read_Only then return St_Read_Only; end if;
      -- H82: the audit log is the fixed append target for now (generic
      -- name-in-shared is deferred with H72).  Snapshot semantics: open the
      -- pre-allocated file and overwrite from offset 0; Write_File is bounded
      -- by File.Size, so the file must already exist or be created here.
      Schild_Schild_Fs.Open ("audit.log", F, Ok);
      if not Ok then
         Schild_Schild_Fs.Create_File ("audit.log", 8192, Ok);
         if not Ok then return St_No_Space; end if;
         Schild_Schild_Fs.Open ("audit.log", F, Ok);
         if not Ok then return St_Io_Error; end if;
      end if;
      if L > 0 then
         Shared_Copy_From (Buf (0)'Address, L);
         Schild_Schild_Fs.Write_File (F, Buf (0 .. Integer (L) - 1), Ok);
         if not Ok then return St_Io_Error; end if;
      end if;
      New_Size := L;
      return St_Ok;
   end Fs_Append;

   function Fs_Get_Entry (Index : Unsigned_32) return Unsigned_32 is
      Ent : Schild_Schild_Fs.Dir_Entry;
      Ok  : Boolean;
      Raw : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31) := (others => 0);
   begin
      Schild_Schild_Fs.Get_Entry (Index, Ent, Ok);
      if not Ok then return St_No_File; end if;
      for I in 0 .. 23 loop
         Raw (I) := Character'Pos (Ent.Name (I + 1));
      end loop;
      Raw (24) := Unsigned_8 (Ent.Start_LBA and 255);
      Raw (25) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 8) and 255);
      Raw (26) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 16) and 255);
      Raw (27) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 24) and 255);
      Raw (28) := Unsigned_8 (Ent.Size and 255);
      Raw (29) := Unsigned_8 (Shift_Right (Ent.Size, 8) and 255);
      Raw (30) := Unsigned_8 (Shift_Right (Ent.Size, 16) and 255);
      Raw (31) := Unsigned_8 (Shift_Right (Ent.Size, 24) and 255);
      Shared_Copy_To (Raw (0)'Address, 32);
      return St_Ok;
   end Fs_Get_Entry;

   function Fs_Is_Mounted return Unsigned_32 is
     (if Schild_Schild_Fs.Is_Mounted then St_Ok else St_Not_Mounted);

   function Fs_Is_Read_Only return Unsigned_32 is
     (if Schild_Schild_Fs.Is_Read_Only then St_Ok else 0);

end Schild_Fs_Server;
