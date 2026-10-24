-- Schild TCB SchildFS — Minimal Read-Only Filesystem
with System; with Interfaces;
with Schild_Nvme; with Schild_Uart_Driver;

package body Schild_Schild_Fs with SPARK_Mode => Off is
   use Interfaces;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   -- CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320). Detects torn or
   -- corrupted metadata blocks (superblock header / root directory) so a
   -- power-loss torn write is observed on the next mount instead of being
   -- silently trusted.
   function CRC32 (Data : Schild_Nvme.Block_Buf; Len : Integer) return Unsigned_32 is
      Crc : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for I in 0 .. Len - 1 loop
         Crc := Crc xor Unsigned_32 (Data (I));
         for J in 1 .. 8 loop
            if (Crc and 1) = 1 then
               Crc := Shift_Right (Crc, 1) xor 16#EDB8_8320#;
            else
               Crc := Shift_Right (Crc, 1);
            end if;
         end loop;
      end loop;
      return not Crc;
   end CRC32;

   Mounted  : Boolean := False;
   Root_Dir : Dir_Table := (others => (Name => (others => ' '),
                                        Start_LBA => 0, Size => 0));
   Entry_Count : Unsigned_32 := 0;

   --  Engaged on CRC32 torn-write detection: blocks all write transactions
   --  until a clean remount.
   Strict_Read_Only : Boolean := False;
   Msg_RO : constant String := "[NVFS] Strict Read-Only: write rejected";

   --  SchildFS lives entirely inside the GPT "free gap" (between the partition
   --  table at LBA 2..33 and the first partition, normally LBA 2048). LBA 0/1
   --  hold the protective MBR / primary GPT header, so the superblocks MUST
   --  NOT touch them. The boot log occupies LBA 2000..2007; SchildFS starts at
   --  LBA 2016 to stay clear of both.
   FS_BASE_LBA        : constant Unsigned_32 := 2016;
   FS_END_LBA         : constant Unsigned_32 := 2048;  -- first-partition guard
   Super_Primary_LBA  : constant Unsigned_32 := FS_BASE_LBA + 0;
   Super_Backup_LBA   : constant Unsigned_32 := FS_BASE_LBA + 1;
   Dir_Primary_LBA    : constant Unsigned_32 := FS_BASE_LBA + 2;
   Dir_Backup_LBA     : constant Unsigned_32 := FS_BASE_LBA + 3;
   Active_Super_LBA   : Unsigned_32 := Super_Primary_LBA;   -- authoritative slot
   Active_Dir_LBA     : Unsigned_32 := Dir_Primary_LBA;     -- authoritative slot
   Current_Generation : Unsigned_32 := 0;  -- generation of the active slot

   procedure Read_Block_512 (LBA : Unsigned_64; Buf : out Schild_Nvme.Block_Buf;
                             Success : out Boolean) is
   begin
      Schild_Nvme.Read_Block (LBA, Success);
      if Success then Buf := Schild_Nvme.Get_Buffer; end if;
   end Read_Block_512;

   procedure Bytes_To_Superblock
     (Raw : in Schild_Nvme.Block_Buf; SB : out Superblock) is
      use type Unsigned_32;
   begin
      SB.Magic := Unsigned_32 (Raw (0)) or Shift_Left (Unsigned_32 (Raw (1)), 8)
        or Shift_Left (Unsigned_32 (Raw (2)), 16)
        or Shift_Left (Unsigned_32 (Raw (3)), 24);
      SB.Version := Unsigned_16 (Raw (4)) or Shift_Left (Unsigned_16 (Raw (5)), 8);
      SB.Root_Dir_LBA := Unsigned_32 (Raw (8)) or Shift_Left (Unsigned_32 (Raw (9)), 8)
        or Shift_Left (Unsigned_32 (Raw (10)), 16)
        or Shift_Left (Unsigned_32 (Raw (11)), 24);
      SB.Root_Entries := Unsigned_32 (Raw (12)) or Shift_Left (Unsigned_32 (Raw (13)), 8)
        or Shift_Left (Unsigned_32 (Raw (14)), 16)
        or Shift_Left (Unsigned_32 (Raw (15)), 24);
      SB.Checksum := Unsigned_32 (Raw (16)) or Shift_Left (Unsigned_32 (Raw (17)), 8)
        or Shift_Left (Unsigned_32 (Raw (18)), 16)
        or Shift_Left (Unsigned_32 (Raw (19)), 24);
      SB.Dir_Checksum := Unsigned_32 (Raw (20)) or Shift_Left (Unsigned_32 (Raw (21)), 8)
        or Shift_Left (Unsigned_32 (Raw (22)), 16)
        or Shift_Left (Unsigned_32 (Raw (23)), 24);
      SB.Generation := Unsigned_32 (Raw (24)) or Shift_Left (Unsigned_32 (Raw (25)), 8)
        or Shift_Left (Unsigned_32 (Raw (26)), 16)
        or Shift_Left (Unsigned_32 (Raw (27)), 24);
   end Bytes_To_Superblock;

   procedure Bytes_To_Dir_Entry
     (Raw : in Schild_Nvme.Block_Buf; Off : in Integer;
      Ent : out Dir_Entry) is
      use type Unsigned_32;
      Base : constant Integer := Off;
   begin
      for I in 0 .. 23 loop
         declare
            C : constant Unsigned_8 := Raw (Base + I);
         begin
            if C in 16#20# .. 16#7E# then
               Ent.Name (I + 1) := Character'Val (C);
            else Ent.Name (I + 1) := ' '; end if;
         end;
      end loop;
      Ent.Start_LBA := Unsigned_32 (Raw (Base + 24))
        or Shift_Left (Unsigned_32 (Raw (Base + 25)), 8)
        or Shift_Left (Unsigned_32 (Raw (Base + 26)), 16)
        or Shift_Left (Unsigned_32 (Raw (Base + 27)), 24);
      Ent.Size := Unsigned_32 (Raw (Base + 28))
        or Shift_Left (Unsigned_32 (Raw (Base + 29)), 8)
        or Shift_Left (Unsigned_32 (Raw (Base + 30)), 16)
        or Shift_Left (Unsigned_32 (Raw (Base + 31)), 24);
   end Bytes_To_Dir_Entry;

   procedure Init (Success : out Boolean) is
      Msg_Mount : constant String := "[NVFS] Mounting filesystem...";
      Msg_SB_CRC : constant String := "[NVFS] Superblock checksum mismatch";
      Msg_Dir_CRC : constant String := "[NVFS] Directory checksum mismatch";
      Msg_OK    : constant String := "[NVFS] Mounted OK";
      Buf : Schild_Nvme.Block_Buf;
      SB_A, SB_B, Chosen : Superblock;
      Have_A, Have_B : Boolean := False;
   begin
      Success := False;
      if not Schild_Nvme.Is_Ready then return; end if;
      C_Putln (Msg_Mount'Address, Msg_Mount'Length);

      --  A/B superblock selection: a slot is valid when its magic and header
      --  CRC match. Pick the valid slot with the higher generation — a torn
      --  (invalid-CRC) primary rolls back to the backup (torn-write recovery).
      Read_Block_512 (Unsigned_64 (Super_Primary_LBA), Buf, Success);
      if Success then
         Bytes_To_Superblock (Buf, SB_A);
         if SB_A.Magic = NVFS_Magic and then CRC32 (Buf, 16) = SB_A.Checksum then
            Have_A := True;
         end if;
      end if;

      Read_Block_512 (Unsigned_64 (Super_Backup_LBA), Buf, Success);
      if Success then
         Bytes_To_Superblock (Buf, SB_B);
         if SB_B.Magic = NVFS_Magic and then CRC32 (Buf, 16) = SB_B.Checksum then
            Have_B := True;
         end if;
      end if;

      if not Have_A and not Have_B then
         C_Putln (Msg_SB_CRC'Address, Msg_SB_CRC'Length);
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         Strict_Read_Only := True;
         Success := False;
         return;
      elsif Have_A and (not Have_B or else SB_A.Generation >= SB_B.Generation) then
         Chosen := SB_A;
         Active_Super_LBA := Super_Primary_LBA;
      else
         Chosen := SB_B;
         Active_Super_LBA := Super_Backup_LBA;
      end if;
      Current_Generation := Chosen.Generation;
      Active_Dir_LBA := Chosen.Root_Dir_LBA;

      Entry_Count := Chosen.Root_Entries;
      if Entry_Count > 16 then Entry_Count := 16; end if;
      Read_Block_512 (Unsigned_64 (Chosen.Root_Dir_LBA), Buf, Success);
      if not Success then return; end if;
      -- Verify the root-directory block CRC (detect a torn directory write).
      if CRC32 (Buf, 512) /= Chosen.Dir_Checksum then
         C_Putln (Msg_Dir_CRC'Address, Msg_Dir_CRC'Length);
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         Strict_Read_Only := True;
         Success := False; return;
      end if;
      for I in 0 .. Integer (Entry_Count) - 1 loop
         Bytes_To_Dir_Entry (Buf, I * 32, Root_Dir (I));
      end loop;
      Mounted := True;
      C_Putln (Msg_OK'Address, Msg_OK'Length);
   end Init;

   function Is_Mounted return Boolean is (Mounted);

   function Is_Read_Only return Boolean is (Strict_Read_Only);

   procedure Open
     (Name    : in     String;
      File    :    out File_Info;
      Success :    out Boolean) is
      Match : Boolean;
   begin
      Success := False; File.Valid := False;
      if not Mounted then return; end if;
      for I in 0 .. Integer (Entry_Count) - 1 loop
         Match := True;
         declare
            Ent : Dir_Entry renames Root_Dir (I);
         begin
            if Name'Length <= Max_Name_Length then
               for J in Name'Range loop
                  if Name (J) /= Ent.Name (J) then
                     Match := False; exit;
                  end if;
               end loop;
               if Match and Name'Length < Max_Name_Length then
                  if Ent.Name (Name'Length + 1) /= ' ' then
                     Match := False;
                  end if;
               end if;
            else Match := False; end if;
            if Match then
               File.Valid := True; File.Name := Ent.Name;
               File.Start_LBA := Ent.Start_LBA; File.Size := Ent.Size;
               File.Curr_Off := 0; Success := True; return;
            end if;
         end;
      end loop;
   end Open;

   procedure Read
     (File    : in out File_Info;
      Buf     :    out Unsigned_8_Array;
      Len     :    out Unsigned_32;
      Success :    out Boolean) is
      Buf_Size  : constant Unsigned_32 := Unsigned_32 (Buf'Length);
      Remaining : Unsigned_32;
      To_Read   : Unsigned_32;
      Block_Buf : Schild_Nvme.Block_Buf;
      LBA_Off   : Unsigned_32;
      Byte_Off  : Unsigned_32;
      Read_OK   : Boolean;
   begin
      Len := 0; Success := False;
      if not File.Valid or File.Curr_Off >= File.Size then return; end if;
      Remaining := File.Size - File.Curr_Off;
      if Buf_Size < Remaining then To_Read := Buf_Size;
      else To_Read := Remaining; end if;
      LBA_Off := File.Start_LBA + (File.Curr_Off / 512);
      Byte_Off := File.Curr_Off rem 512;
      Read_Block_512 (Unsigned_64 (LBA_Off), Block_Buf, Read_OK);
      if not Read_OK then return; end if;
      declare
         Copied : Unsigned_32 := 0;
         Off    : Unsigned_32 := Byte_Off;
      begin
         while Copied < To_Read loop
            exit when Off >= 512;
            Buf (Integer (Copied)) := Block_Buf (Integer (Off));
            Copied := Copied + 1; Off := Off + 1;
         end loop;
         File.Curr_Off := File.Curr_Off + Copied;
         Len := Copied; Success := True;
      end;
   end Read;

   -- Stage 7.8: WRITE SUPPORT

   procedure Write_Block_512 (LBA : Unsigned_64; Data : Schild_Nvme.Block_Buf;
                              Success : out Boolean) is
   begin
      Schild_Nvme.Fill_Buffer (Data);
      Schild_Nvme.Write_Block (LBA, Success);
   end Write_Block_512;

   procedure Superblock_To_Bytes (SB : Superblock; Raw : out Schild_Nvme.Block_Buf) is
   begin
      Raw := (others => 0);
      Raw (0) := Unsigned_8 (SB.Magic and 255);
      Raw (1) := Unsigned_8 (Shift_Right (SB.Magic, 8) and 255);
      Raw (2) := Unsigned_8 (Shift_Right (SB.Magic, 16) and 255);
      Raw (3) := Unsigned_8 (Shift_Right (SB.Magic, 24) and 255);
      Raw (4) := Unsigned_8 (SB.Version and 255);
      Raw (5) := Unsigned_8 (Shift_Right (SB.Version, 8) and 255);
      Raw (8) := Unsigned_8 (SB.Root_Dir_LBA and 255);
      Raw (9) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 8) and 255);
      Raw (10) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 16) and 255);
      Raw (11) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 24) and 255);
      Raw (12) := Unsigned_8 (SB.Root_Entries and 255);
      Raw (13) := Unsigned_8 (Shift_Right (SB.Root_Entries, 8) and 255);
      Raw (14) := Unsigned_8 (Shift_Right (SB.Root_Entries, 16) and 255);
      Raw (15) := Unsigned_8 (Shift_Right (SB.Root_Entries, 24) and 255);
      Raw (16) := Unsigned_8 (SB.Checksum and 255);
      Raw (17) := Unsigned_8 (Shift_Right (SB.Checksum, 8) and 255);
      Raw (18) := Unsigned_8 (Shift_Right (SB.Checksum, 16) and 255);
      Raw (19) := Unsigned_8 (Shift_Right (SB.Checksum, 24) and 255);
      Raw (20) := Unsigned_8 (SB.Dir_Checksum and 255);
      Raw (21) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 8) and 255);
      Raw (22) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 16) and 255);
      Raw (23) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 24) and 255);
      Raw (24) := Unsigned_8 (SB.Generation and 255);
      Raw (25) := Unsigned_8 (Shift_Right (SB.Generation, 8) and 255);
      Raw (26) := Unsigned_8 (Shift_Right (SB.Generation, 16) and 255);
      Raw (27) := Unsigned_8 (Shift_Right (SB.Generation, 24) and 255);
   end Superblock_To_Bytes;

   procedure Dir_Entry_To_Bytes (Ent : Dir_Entry; Raw : out Schild_Nvme.Block_Buf;
                                 Off : Integer) is
   begin
      for I in 0 .. 23 loop
         if I < Ent.Name'Length then
            Raw (Off + I) := Unsigned_8 (Character'Pos (Ent.Name (I + 1)));
         else Raw (Off + I) := 0; end if;
      end loop;
      Raw (Off + 24) := Unsigned_8 (Ent.Start_LBA and 255);
      Raw (Off + 25) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 8) and 255);
      Raw (Off + 26) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 16) and 255);
      Raw (Off + 27) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 24) and 255);
      Raw (Off + 28) := Unsigned_8 (Ent.Size and 255);
      Raw (Off + 29) := Unsigned_8 (Shift_Right (Ent.Size, 8) and 255);
      Raw (Off + 30) := Unsigned_8 (Shift_Right (Ent.Size, 16) and 255);
      Raw (Off + 31) := Unsigned_8 (Shift_Right (Ent.Size, 24) and 255);
   end Dir_Entry_To_Bytes;

   Next_Free_LBA : Unsigned_32 := FS_BASE_LBA + 4;

   procedure Create_File (Name : in String; Size : in Unsigned_32;
                          Success : out Boolean) is
      Msg_Full : constant String := "[NVFS] Directory full";
      Msg_NoSpace : constant String := "[NVFS] No space in GPT gap";
      Msg_OK   : constant String := "[NVFS] File created";
   begin
      Success := False;
      if not Mounted then return; end if;
      if Strict_Read_Only then
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         return;
      end if;
      if Entry_Count >= 16 then
         C_Putln (Msg_Full'Address, Msg_Full'Length);
         return;
      end if;
      --  Data-region guard: never let file data grow past the GPT gap into the
      --  first partition (which would corrupt a real GPT disk).
      if Next_Free_LBA + (Size + 511) / 512 > FS_END_LBA then
         C_Putln (Msg_NoSpace'Address, Msg_NoSpace'Length);
         return;
      end if;
      declare
         Ent : Dir_Entry := (Name => (others => ' '), Start_LBA => Next_Free_LBA, Size => Size);
      begin
         for J in Name'Range loop exit when J > Max_Name_Length;
            Ent.Name (J) := Name (J); end loop;
         Root_Dir (Integer (Entry_Count)) := Ent;
      end;
      Entry_Count := Entry_Count + 1;
      -- Flush directory + superblock (superblock is the commit point).
      declare
         Dir_Buf : Schild_Nvme.Block_Buf := (others => 0);
         SB_Buf  : Schild_Nvme.Block_Buf;
         SB      : Superblock := (Magic => NVFS_Magic, Version => 1,
                                  Block_Size => 512, Root_Dir_LBA => Dir_Primary_LBA,
                                  Root_Entries => Entry_Count,
                                  Checksum => 0, Dir_Checksum => 0,
                                  Generation => Current_Generation + 1);
         Dir_CRC : Unsigned_32;
         OK : Boolean;
      begin
         for I in 0 .. Integer (Entry_Count) - 1 loop
            Dir_Entry_To_Bytes (Root_Dir (I), Dir_Buf, I * 32);
         end loop;
         -- Commit: checksum the directory, then the superblock header. Write
         -- the directory to the INACTIVE directory slot and the superblock to
         -- the INACTIVE superblock slot, so a power loss mid-write leaves the
         -- previous (directory, superblock) pair intact for rollback.
         Dir_CRC := CRC32 (Dir_Buf, 512);
         SB.Dir_Checksum := Dir_CRC;
         SB.Root_Dir_LBA := (if Active_Dir_LBA = Dir_Primary_LBA then Dir_Backup_LBA
                             else Dir_Primary_LBA);
         Superblock_To_Bytes (SB, SB_Buf);
         SB.Checksum := CRC32 (SB_Buf, 16);
         Superblock_To_Bytes (SB, SB_Buf);
         Write_Block_512 (Unsigned_64 (SB.Root_Dir_LBA), Dir_Buf, OK);
         Write_Block_512 (Unsigned_64 (if Active_Super_LBA = Super_Primary_LBA
                                       then Super_Backup_LBA
                                       else Super_Primary_LBA), SB_Buf, OK);
         Active_Dir_LBA := SB.Root_Dir_LBA;
         Active_Super_LBA := (if Active_Super_LBA = Super_Primary_LBA
                              then Super_Backup_LBA
                              else Super_Primary_LBA);
         Current_Generation := SB.Generation;
      end;
      Next_Free_LBA := Next_Free_LBA + (Size + 511) / 512;
      Success := True;
      C_Putln (Msg_OK'Address, Msg_OK'Length);
   end Create_File;

   procedure Write_File (File : in out File_Info; Data : in Unsigned_8_Array;
                         Success : out Boolean) is
      Wr_Pos   : Unsigned_32 := File.Curr_Off;
      D_Pos    : Unsigned_32 := 0;
      LBA_Off  : Unsigned_32;
      Byte_Off : Unsigned_32;
      Block_Buf : Schild_Nvme.Block_Buf;
      Wr_OK    : Boolean;
   begin
      Success := False;
      if Strict_Read_Only then return; end if;
      if not File.Valid then return; end if;
      if Wr_Pos + Unsigned_32 (Data'Length) > File.Size then return; end if;
      while D_Pos < Unsigned_32 (Data'Length) loop
         LBA_Off := File.Start_LBA + (Wr_Pos / 512);
         Byte_Off := Wr_Pos rem 512;
         Read_Block_512 (Unsigned_64 (LBA_Off), Block_Buf, Wr_OK);
         if not Wr_OK then return; end if;
         declare
            Space : Unsigned_32 := 512 - Byte_Off;
            To_Write : Unsigned_32 := Unsigned_32 (Data'Length) - D_Pos;
         begin
            if To_Write > Space then To_Write := Space; end if;
            for I in 0 .. Integer (To_Write) - 1 loop
               Block_Buf (Integer (Byte_Off + Unsigned_32 (I))) :=
                 Data (Integer (D_Pos + Unsigned_32 (I)));
            end loop;
            Schild_Nvme.Fill_Buffer (Block_Buf);
            Schild_Nvme.Write_Block (Unsigned_64 (LBA_Off), Wr_OK);
            if not Wr_OK then return; end if;
            Wr_Pos := Wr_Pos + To_Write;
            D_Pos := D_Pos + To_Write;
         end;
      end loop;
      File.Curr_Off := Wr_Pos;
      Success := True;
   end Write_File;

   procedure Get_Entry
     (Index   : in     Unsigned_32;
      Dir_Ent :    out Dir_Entry;
      Success :    out Boolean) is
   begin
      if not Mounted or Index >= Entry_Count then
         Success := False;
         Dir_Ent := (Name => (others => ' '), Start_LBA => 0, Size => 0);
         return;
      end if;
      Dir_Ent := Root_Dir (Integer (Index)); Success := True;
   end Get_Entry;

end Schild_Schild_Fs;
