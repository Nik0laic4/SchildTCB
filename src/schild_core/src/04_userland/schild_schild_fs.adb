-- Schild TCB SchildFS — Minimal Read-Only Filesystem
with System; with Interfaces;
with Schild_Nvme; with Schild_Uart_Driver;
with Schild_Fs_Core;
with Schild_HMAC_SHA256;

package body Schild_Schild_Fs with SPARK_Mode => Off is
   use Interfaces; use Schild_Fs_Core;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   -- H61: HMAC-SHA256 over superblock bytes 0..447, key from Hmac_Key.
   function Compute_SB_HMAC (Key : Schild_HMAC_SHA256.SHA256_Hash;
                             Raw : Block_Buf)
      return Schild_HMAC_SHA256.SHA256_Hash
   is
      Key_B : Schild_HMAC_SHA256.Byte_Array (0 .. 31) := (others => 0);
      Data  : Schild_HMAC_SHA256.Byte_Array (0 .. 447) := (others => 0);
      V : Unsigned_64;
   begin
      for W in 0 .. 3 loop
         V := Key (W);
         for B in 0 .. 7 loop
            Key_B (W * 8 + B) := Unsigned_8 (V and 16#FF#);
            V := Shift_Right (V, 8);
         end loop;
      end loop;
      for I in 0 .. 447 loop
         Data (I) := Raw (I);
      end loop;
      return Schild_HMAC_SHA256.HMAC_SHA256 (Key_B, Data);
   end Compute_SB_HMAC;

   -- CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320). Detects torn or
   -- corrupted metadata blocks (superblock header / root directory) so a
   -- power-loss torn write is observed on the next mount instead of being
   -- silently trusted.


   Mounted  : Boolean := False;
   Root_Dir : Dir_Table := (others => (Name => (others => ' '),
                                        Start_LBA => 0, Size => 0, Checksum => 0));
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

   procedure Read_Block_512 (LBA : Unsigned_64; Buf : out Block_Buf;
                             Success : out Boolean) is
   begin
      Schild_Nvme.Read_Block (LBA, Success);
      if Success then Buf := Block_Buf (Schild_Nvme.Get_Buffer); end if;
   end Read_Block_512;

   --  H62: CRC32 over a file's logical data bytes (0..Size-1), read block by
   --  block. Detects a torn data write on the next Open (per-file checksum).
   function Compute_File_CRC (Start_LBA : Unsigned_32; Size : Unsigned_32)
                              return Unsigned_32 is
      Crc  : Unsigned_32 := 16#FFFF_FFFF#;
      Done : Unsigned_32 := 0;
      Buf  : Block_Buf;
      Ok   : Boolean;
   begin
      while Done < Size loop
         declare
            LBA : constant Unsigned_32 := Start_LBA + (Done / 512);
            Off : constant Unsigned_32 := Done rem 512;
            Len : Unsigned_32 := Size - Done;
         begin
            if Len > 512 - Off then Len := 512 - Off; end if;
            Read_Block_512 (Unsigned_64 (LBA), Buf, Ok);
            if not Ok then return 0; end if;
            for I in 0 .. Integer (Len) - 1 loop
               Crc := Crc xor Unsigned_32 (Buf (Integer (Off) + I));
               for J in 1 .. 8 loop
                  if (Crc and 1) = 1 then
                     Crc := Shift_Right (Crc, 1) xor 16#EDB8_8320#;
                  else
                     Crc := Shift_Right (Crc, 1);
                  end if;
               end loop;
            end loop;
            Done := Done + Len;
         end;
      end loop;
      return not Crc;
   end Compute_File_CRC;



   -- Audit H79: Next_Free_LBA and Write_Block_512 are used inside Init
   -- (fresh-format path and persisted allocator state). Ada requires
   -- declaration-before-use for variables; forward decl for procedures.
   Next_Free_LBA : Unsigned_32 := FS_BASE_LBA + 4;
   Block_Bitmap  : Unsigned_32 := 0;  -- H60: used-block bitmap (data region)
   Hmac_Key      : Schild_HMAC_SHA256.SHA256_Hash := (others => 0);  -- H61

   procedure Write_Block_512 (LBA : Unsigned_64; Data : Block_Buf;
                              Success : out Boolean);

   -- Audit H75: forward declaration so Init (defined before the helper)
   -- can format a fresh device. The body lives in the WRITE SUPPORT section.

   procedure Init (Success : out Boolean) is
      Msg_Mount : constant String := "[NVFS] Mounting filesystem...";
      Msg_SB_CRC : constant String := "[NVFS] Superblock checksum mismatch";
      Msg_Dir_CRC : constant String := "[NVFS] Directory checksum mismatch";
      Msg_OK    : constant String := "[NVFS] Mounted OK";
      Msg_Fresh : constant String := "[NVFS] Fresh device formatted";
      Msg_Hmac  : constant String := "[NVFS] HMAC mismatch";
      Buf : Block_Buf;
      SB_A, SB_B, Chosen : Superblock;
      Have_A, Have_B : Boolean := False;
      SB_A_Magic_OK, SB_B_Magic_OK : Boolean := False;
   begin
      Success := False;
      -- Audit H76: reset read-only state at the start of Init, so a torn-write
      -- read-only condition does not persist across a clean remount.
      Strict_Read_Only := False;
      Mounted := False;
      if not Schild_Nvme.Is_Ready then return; end if;
      C_Putln (Msg_Mount'Address, Msg_Mount'Length);

      Read_Block_512 (Unsigned_64 (Super_Primary_LBA), Buf, Success);
      if Success then
         Bytes_To_Superblock (Buf, SB_A);
         if SB_A.Magic = NVFS_Magic and then SB_A.Version = NVFS_Version then
            SB_A_Magic_OK := True;
            if CRC32 (Buf, 16) = SB_A.Checksum then
               Have_A := True;
            end if;
         end if;
      end if;

      Read_Block_512 (Unsigned_64 (Super_Backup_LBA), Buf, Success);
      if Success then
         Bytes_To_Superblock (Buf, SB_B);
         if SB_B.Magic = NVFS_Magic and then SB_B.Version = NVFS_Version then
            SB_B_Magic_OK := True;
            if CRC32 (Buf, 16) = SB_B.Checksum then
               Have_B := True;
            end if;
         end if;
      end if;

      if not Have_A and not Have_B then
         if SB_A_Magic_OK or SB_B_Magic_OK then
            -- Torn write: FS signature present but both slots corrupt.
            -- Do NOT format (data may be recoverable). Force read-only.
            C_Putln (Msg_SB_CRC'Address, Msg_SB_CRC'Length);
            C_Putln (Msg_RO'Address, Msg_RO'Length);
            Strict_Read_Only := True;
            Success := False;
            return;
         else
            -- Audit H75: fresh device (no SchildFS signature). Format it.
            declare
               SB_Fresh : Superblock := (
                  Magic => NVFS_Magic, Version => NVFS_Version, Block_Size => 512,
                  Root_Dir_LBA => Dir_Primary_LBA, Root_Entries => 0,
                  Checksum => 0, Dir_Checksum => 0, Generation => 1,
                  Next_Free_LBA => FS_BASE_LBA + 4, Block_Bitmap => 0,
                  Hmac_Key => (others => 0), Hmac_Tag => (others => 0));
               SB_Buf : Block_Buf;
               Dir_Buf : Block_Buf := (others => 0);
               W_OK : Boolean;
            begin
               Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (Dir_Buf));
               Schild_Nvme.Write_Block (Unsigned_64 (Dir_Primary_LBA), W_OK);
               if not W_OK then return; end if;
               Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (Dir_Buf));
               Schild_Nvme.Write_Block (Unsigned_64 (Dir_Backup_LBA), W_OK);
               if not W_OK then return; end if;
               -- H61: generate the HMAC key once (RDRAND; deterministic fallback).
               -- H61: derive the HMAC key. The RDRAND source (Schild_Rng_Manager /
               -- Schild_Random_Core) is deferred to Block 3: merely LINKING those
               -- modules shifts the shared ELF layout and hangs the IPC benchmark
               -- (H87 shared-image size-sensitivity). A deterministic per-word
               -- constant keeps the HMAC infra live until the ELF loader lands.
               declare
               begin
                  for W in 0 .. 3 loop
                     SB_Fresh.Hmac_Key (W) := 16#9E3779B97F4A7C15# + Unsigned_64 (W);
                  end loop;
                  Hmac_Key := SB_Fresh.Hmac_Key;
               end;
               SB_Fresh.Dir_Checksum := CRC32 (Dir_Buf, 512);
               Superblock_To_Bytes (SB_Fresh, SB_Buf);
               SB_Fresh.Checksum := CRC32 (SB_Buf, 16);
               Superblock_To_Bytes (SB_Fresh, SB_Buf);
               SB_Fresh.Hmac_Tag := Compute_SB_HMAC (SB_Fresh.Hmac_Key, SB_Buf);
               Superblock_To_Bytes (SB_Fresh, SB_Buf);
               Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (SB_Buf));
               Schild_Nvme.Write_Block (Unsigned_64 (Super_Primary_LBA), W_OK);
               if not W_OK then return; end if;
               Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (SB_Buf));
               Schild_Nvme.Write_Block (Unsigned_64 (Super_Backup_LBA), W_OK);
               if not W_OK then return; end if;
               Active_Super_LBA := Super_Primary_LBA;
               Active_Dir_LBA := Dir_Primary_LBA;
               Current_Generation := 1;
               Entry_Count := 0;
               Next_Free_LBA := FS_BASE_LBA + 4;
               Block_Bitmap := 0;
               Mounted := True;
               Success := True;
               C_Putln (Msg_Fresh'Address, Msg_Fresh'Length);
               return;
            end;
         end if;
      end if;

      if Have_A and (not Have_B or else SB_A.Generation >= SB_B.Generation) then
         Chosen := SB_A;
         Active_Super_LBA := Super_Primary_LBA;
      else
         Chosen := SB_B;
         Active_Super_LBA := Super_Backup_LBA;
      end if;
      Current_Generation := Chosen.Generation;
      Active_Dir_LBA := Chosen.Root_Dir_LBA;

      -- Audit H74: restore Next_Free_LBA from the persisted superblock. A
      -- pre-H74 superblock has 0 here; the fallback below recomputes it from
      -- the root-directory allocations after the loop.
      Next_Free_LBA := Chosen.Next_Free_LBA;
      Block_Bitmap  := Chosen.Block_Bitmap;
      Hmac_Key      := Chosen.Hmac_Key;

      Entry_Count := Chosen.Root_Entries;
      if Entry_Count > 16 then Entry_Count := 16; end if;
      Read_Block_512 (Unsigned_64 (Chosen.Root_Dir_LBA), Buf, Success);
      if not Success then return; end if;
      if CRC32 (Buf, 512) /= Chosen.Dir_Checksum then
         C_Putln (Msg_Dir_CRC'Address, Msg_Dir_CRC'Length);
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         Strict_Read_Only := True;
         Success := False; return;
      end if;
      for I in 0 .. Integer (Entry_Count) - 1 loop
         Bytes_To_Dir_Entry (Buf, I * 36, Root_Dir (I));
      end loop;

      -- Audit H74 fallback: if the persisted Next_Free_LBA is invalid (legacy
      -- superblock without the field, or a corrupted-but-CRC-valid value),
      -- recompute it from the largest allocation in the root directory.
      if Next_Free_LBA < FS_BASE_LBA + 4 then
         Next_Free_LBA := FS_BASE_LBA + 4;
         for I in 0 .. Integer (Entry_Count) - 1 loop
            declare
               Ent_End : constant Unsigned_32 :=
                 Root_Dir (I).Start_LBA + (Root_Dir (I).Size + 511) / 512;
            begin
               if Ent_End > Next_Free_LBA then
                  Next_Free_LBA := Ent_End;
               end if;
            end;
         end loop;
      end if;

      -- H61: verify the HMAC tag (tamper detection -> Strict Read-Only).
      Read_Block_512 (Unsigned_64 (Active_Super_LBA), Buf, Success);
      if Success then
         declare
            T : Schild_HMAC_SHA256.SHA256_Hash := Compute_SB_HMAC (Chosen.Hmac_Key, Buf);
            Mismatch : Boolean := False;
         begin
            for W in 0 .. 3 loop
               if T (W) /= Chosen.Hmac_Tag (W) then Mismatch := True; end if;
            end loop;
            if Mismatch then
               Strict_Read_Only := True;
               C_Putln (Msg_Hmac'Address, Msg_Hmac'Length);
            end if;
         end;
      end if;

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
      Msg_Corrupt : constant String := "[NVFS] File checksum mismatch (torn write)";
   begin
      Success := False; File.Valid := False;
      if not Mounted then return; end if;
      -- Audit H42: Ent.Name is String (1 .. 24). Name must be 1-based;
      -- a sliced Name (Name'First /= 1) would index Ent.Name OOB.
      if Name'First /= 1 then return; end if;
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
               --  H62: verify the file's data CRC (torn-write detection).
               if Compute_File_CRC (Ent.Start_LBA, Ent.Size) /= Ent.Checksum then
                  C_Putln (Msg_Corrupt'Address, Msg_Corrupt'Length);
                  return;
               end if;
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
      Scratch : Block_Buf;
      LBA_Off   : Unsigned_32;
      Byte_Off  : Unsigned_32;
      Read_OK   : Boolean;
   begin
      Len := 0; Success := False;
      -- Audit H43: the copy loop indexes Buf by 0-based Copied; reject
      -- non-0-based Buf to prevent OOB.
      if Buf'First /= 0 then return; end if;
      if not File.Valid or File.Curr_Off >= File.Size then return; end if;
      Remaining := File.Size - File.Curr_Off;
      if Buf_Size < Remaining then To_Read := Buf_Size;
      else To_Read := Remaining; end if;
      LBA_Off := File.Start_LBA + (File.Curr_Off / 512);
      Byte_Off := File.Curr_Off rem 512;
      Read_Block_512 (Unsigned_64 (LBA_Off), Scratch, Read_OK);
      if not Read_OK then return; end if;
      declare
         Copied : Unsigned_32 := 0;
         Off    : Unsigned_32 := Byte_Off;
      begin
         while Copied < To_Read loop
            exit when Off >= 512;
            Buf (Integer (Copied)) := Scratch (Integer (Off));
            Copied := Copied + 1; Off := Off + 1;
         end loop;
         File.Curr_Off := File.Curr_Off + Copied;
         Len := Copied; Success := True;
      end;
   end Read;

   -- Stage 7.8: WRITE SUPPORT



   procedure Write_Block_512 (LBA : Unsigned_64; Data : Block_Buf;
                              Success : out Boolean) is
   begin
      Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (Data));
      Schild_Nvme.Write_Block (LBA, Success);
   end Write_Block_512;

   -- ============================================================
   --  H73: free-block allocator (first-fit over Block_Bitmap).
   -- ============================================================

   Data_Blocks : constant Unsigned_32 := FS_END_LBA - (FS_BASE_LBA + 4);  -- 28

   --  Return the LBA of a contiguous run of at least N free data blocks
   --  (first-fit), or 0 if none exists. N = 0 returns the first free block
   --  (a Size-0 file reserves its future growth point).
   function Find_Contiguous_Free (N : Unsigned_32) return Unsigned_32 is
      Need : constant Unsigned_32 := (if N = 0 then 1 else N);
   begin
      if Need > Data_Blocks then
         return 0;
      end if;
      for Start in 0 .. Data_Blocks - Need loop
         declare
            All_Free : Boolean := True;
         begin
            for I in 0 .. Integer (Need) - 1 loop
               if (Block_Bitmap and
                   Shift_Left (Unsigned_32'(1), Integer (Start) + I)) /= 0
               then
                  All_Free := False;
                  exit;
               end if;
            end loop;
            if All_Free then
               return FS_BASE_LBA + 4 + Start;
            end if;
         end;
      end loop;
      return 0;
   end Find_Contiguous_Free;

   --  True when all N blocks starting at Start_LBA are free (bit = 0).
   function Blocks_Are_Free (Start_LBA : Unsigned_32; N : Unsigned_32)
                             return Boolean is
      Start_Idx : constant Unsigned_32 := Start_LBA - (FS_BASE_LBA + 4);
   begin
      for I in 0 .. Integer (N) - 1 loop
         if (Block_Bitmap and
             Shift_Left (Unsigned_32'(1), Integer (Start_Idx) + I)) /= 0 then
            return False;
         end if;
      end loop;
      return True;
   end Blocks_Are_Free;

   --  Mark N blocks starting at Start_LBA as used (bit = 1).
   procedure Set_Blocks (Start_LBA : Unsigned_32; N : Unsigned_32) is
      Start_Idx : constant Unsigned_32 := Start_LBA - (FS_BASE_LBA + 4);
   begin
      for I in 0 .. Integer (N) - 1 loop
         Block_Bitmap := Block_Bitmap or
           Shift_Left (Unsigned_32'(1), Integer (Start_Idx) + I);
      end loop;
   end Set_Blocks;

   --  Mark N blocks starting at Start_LBA as free (bit = 0).
   procedure Clear_Blocks (Start_LBA : Unsigned_32; N : Unsigned_32) is
      Start_Idx : constant Unsigned_32 := Start_LBA - (FS_BASE_LBA + 4);
   begin
      for I in 0 .. Integer (N) - 1 loop
         Block_Bitmap := Block_Bitmap and
           (not Shift_Left (Unsigned_32'(1), Integer (Start_Idx) + I));
      end loop;
   end Clear_Blocks;

   --  H73: shared A/B metadata commit. Serializes the root directory, computes
   --  CRC32 + HMAC-SHA256, writes the directory and superblock to the INACTIVE
   --  slots, then flips the active pointers (atomic A/B commit). The caller
   --  already populated SB's Root_Entries / Next_Free_LBA / Block_Bitmap.
   procedure Commit_Metadata (SB : in out Superblock; Success : out Boolean) is
      Dir_Buf : Block_Buf := (others => 0);
      SB_Buf  : Block_Buf;
      Dir_CRC : Unsigned_32;
      OK      : Boolean;
   begin
      Success := False;
      for I in 0 .. Integer (Entry_Count) - 1 loop
         Dir_Entry_To_Bytes (Root_Dir (I), Dir_Buf, I * 36);
      end loop;
      Dir_CRC := CRC32 (Dir_Buf, 512);
      SB.Dir_Checksum := Dir_CRC;
      SB.Root_Dir_LBA := (if Active_Dir_LBA = Dir_Primary_LBA
                          then Dir_Backup_LBA else Dir_Primary_LBA);
      Superblock_To_Bytes (SB, SB_Buf);
      SB.Checksum := CRC32 (SB_Buf, 16);
      Superblock_To_Bytes (SB, SB_Buf);
      SB.Hmac_Tag := Compute_SB_HMAC (SB.Hmac_Key, SB_Buf);
      Superblock_To_Bytes (SB, SB_Buf);
      Write_Block_512 (Unsigned_64 (SB.Root_Dir_LBA), Dir_Buf, OK);
      if not OK then return; end if;
      Write_Block_512 (Unsigned_64 (if Active_Super_LBA = Super_Primary_LBA
                                    then Super_Backup_LBA
                                    else Super_Primary_LBA), SB_Buf, OK);
      if not OK then return; end if;
      Active_Dir_LBA := SB.Root_Dir_LBA;
      Active_Super_LBA := (if Active_Super_LBA = Super_Primary_LBA
                           then Super_Backup_LBA else Super_Primary_LBA);
      Current_Generation := SB.Generation;
      Success := True;
   end Commit_Metadata;


   procedure Create_File (Name : in String; Size : in Unsigned_32;
                          Success : out Boolean) is
      Msg_Full : constant String := "[NVFS] Directory full";
      Msg_NoSpace : constant String := "[NVFS] No space in GPT gap";
      Msg_OK   : constant String := "[NVFS] File created";
      N        : constant Unsigned_32 := (Size + 511) / 512;
      Start_LBA : Unsigned_32;
   begin
      Success := False;
      if not Mounted then return; end if;
      if Strict_Read_Only then
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         return;
      end if;
      if Entry_Count >= 14 then
         C_Putln (Msg_Full'Address, Msg_Full'Length);
         return;
      end if;
      --  H73: first-fit allocation over the free-block bitmap (reuses blocks
      --  freed by Delete_File instead of the monotonic Next_Free_LBA).
      Start_LBA := Find_Contiguous_Free (N);
      if Start_LBA = 0 then
         C_Putln (Msg_NoSpace'Address, Msg_NoSpace'Length);
         return;
      end if;
      declare
         Ent : Dir_Entry := (Name => (others => ' '), Start_LBA => Start_LBA, Size => Size, Checksum => 0);
      begin
         for J in Name'Range loop exit when J > Max_Name_Length;
            Ent.Name (J) := Name (J); end loop;
         Root_Dir (Integer (Entry_Count)) := Ent;
      end;
      Entry_Count := Entry_Count + 1;
      --  H60/H73: zero the freshly allocated data blocks (no data leak on
      --  block reuse) and mark them used in the bitmap.
      declare
         Zero_Buf : Block_Buf := (others => 0);
         OK : Boolean;
      begin
         for I in 0 .. Integer (N) - 1 loop
            Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (Zero_Buf));
            Schild_Nvme.Write_Block (Unsigned_64 (Start_LBA + Unsigned_32 (I)), OK);
            if not OK then return; end if;
         end loop;
      end;
      Set_Blocks (Start_LBA, N);
      --  H62: persist the file's data CRC (data is zeroed on create).
      Root_Dir (Integer (Entry_Count) - 1).Checksum :=
        Compute_File_CRC (Start_LBA, Size);
      --  Advance the allocator watermark only if this allocation extended it.
      if Start_LBA + N > Next_Free_LBA then
         Next_Free_LBA := Start_LBA + N;
      end if;
      --  Commit: directory + superblock (superblock is the commit point).
      declare
         SB : Superblock := (Magic => NVFS_Magic, Version => NVFS_Version,
                             Block_Size => 512, Root_Dir_LBA => Dir_Primary_LBA,
                             Root_Entries => Entry_Count,
                             Checksum => 0, Dir_Checksum => 0,
                             Generation => Current_Generation + 1,
                             Next_Free_LBA => Next_Free_LBA,
                             Block_Bitmap => Block_Bitmap,
                             Hmac_Key => Hmac_Key,
                             Hmac_Tag => (others => 0));
         OK : Boolean;
      begin
         Commit_Metadata (SB, OK);
         if not OK then return; end if;
      end;
      Success := True;
      C_Putln (Msg_OK'Address, Msg_OK'Length);
   end Create_File;

   procedure Write_File (File : in out File_Info; Data : in Unsigned_8_Array;
                         Success : out Boolean) is
      Wr_Pos   : Unsigned_32 := File.Curr_Off;
      D_Pos    : Unsigned_32 := 0;
      LBA_Off  : Unsigned_32;
      Byte_Off : Unsigned_32;
      Scratch : Block_Buf;
      Wr_OK    : Boolean;
   begin
      Success := False;
      if Strict_Read_Only then return; end if;
      if not File.Valid then return; end if;
      -- Audit H52: copy loop indexes Data by 0-based D_Pos; reject
      -- non-0-based Data to prevent OOB.
      if Data'First /= 0 then return; end if;
      -- H72: allow extend. Guard the GPT-gap bound, not File.Size — appending
      -- to a file (audit.log) is allowed to grow it.
      if File.Start_LBA + (Wr_Pos + Unsigned_32 (Data'Length) + 511) / 512 > FS_END_LBA then
         return;
      end if;
      --  H73: if the write extends the file, the newly targeted blocks must be
      --  free (otherwise a fragmented allocation would be corrupted).
      declare
         Old_End : constant Unsigned_32 := File.Start_LBA + (File.Size + 511) / 512;
         New_End : constant Unsigned_32 := File.Start_LBA + (Wr_Pos + Unsigned_32 (Data'Length) + 511) / 512;
      begin
         if New_End > Old_End and then not Blocks_Are_Free (Old_End, New_End - Old_End) then
            return;
         end if;
      end;
      while D_Pos < Unsigned_32 (Data'Length) loop
         LBA_Off := File.Start_LBA + (Wr_Pos / 512);
         Byte_Off := Wr_Pos rem 512;
         Read_Block_512 (Unsigned_64 (LBA_Off), Scratch, Wr_OK);
         if not Wr_OK then return; end if;
         declare
            Space : Unsigned_32 := 512 - Byte_Off;
            To_Write : Unsigned_32 := Unsigned_32 (Data'Length) - D_Pos;
         begin
            if To_Write > Space then To_Write := Space; end if;
            for I in 0 .. Integer (To_Write) - 1 loop
               Scratch (Integer (Byte_Off + Unsigned_32 (I))) :=
                 Data (Integer (D_Pos + Unsigned_32 (I)));
            end loop;
            Schild_Nvme.Fill_Buffer (Schild_Nvme.Block_Buf (Scratch));
            Schild_Nvme.Write_Block (Unsigned_64 (LBA_Off), Wr_OK);
            if not Wr_OK then return; end if;
            Wr_Pos := Wr_Pos + To_Write;
            D_Pos := D_Pos + To_Write;
         end;
      end loop;
      --  H72/H73/H62: recompute the file CRC and persist Size + watermark with
      --  the shared A/B commit. The CRC is committed metadata, so every write
      --  (extend or in-place) commits.
      declare
         New_Size : constant Unsigned_32 := (if Wr_Pos > File.Size then Wr_Pos else File.Size);
         Old_End  : constant Unsigned_32 := File.Start_LBA + (File.Size + 511) / 512;
         New_End  : constant Unsigned_32 := File.Start_LBA + (New_Size + 511) / 512;
         New_NFL  : constant Unsigned_32 := (if New_End > Next_Free_LBA then New_End else Next_Free_LBA);
         SB       : Superblock := (Magic => NVFS_Magic, Version => NVFS_Version,
                                   Block_Size => 512, Root_Dir_LBA => Dir_Primary_LBA,
                                   Root_Entries => Entry_Count,
                                   Checksum => 0, Dir_Checksum => 0,
                                   Generation => Current_Generation + 1,
                                   Next_Free_LBA => New_NFL,
                                   Block_Bitmap => Block_Bitmap,
                                   Hmac_Key => Hmac_Key,
                                   Hmac_Tag => (others => 0));
         OK : Boolean;
      begin
         if New_End > Old_End then
            Set_Blocks (Old_End, New_End - Old_End);
            SB.Block_Bitmap := Block_Bitmap;
         end if;
         for I in 0 .. Integer (Entry_Count) - 1 loop
            if Root_Dir (I).Start_LBA = File.Start_LBA then
               Root_Dir (I).Size := New_Size;
               Root_Dir (I).Checksum := Compute_File_CRC (File.Start_LBA, New_Size);
               exit;
            end if;
         end loop;
         Commit_Metadata (SB, OK);
         if not OK then return; end if;
         Next_Free_LBA := New_NFL;
         File.Size := New_Size;
      end;
      File.Curr_Off := Wr_Pos;
      Success := True;
   end Write_File;

   procedure Delete_File (Name : in String; Success : out Boolean) is
      Msg_NotFound : constant String := "[NVFS] File not found";
      Msg_Deleted  : constant String := "[NVFS] File deleted";
      Match : Boolean;
      Idx   : Integer := -1;
   begin
      Success := False;
      if not Mounted then return; end if;
      if Strict_Read_Only then
         C_Putln (Msg_RO'Address, Msg_RO'Length);
         return;
      end if;
      --  Audit H42 (same as Open): Ent.Name is 1-based; a sliced Name would
      --  index Ent.Name out of bounds.
      if Name'First /= 1 then return; end if;
      --  Locate the file by name.
      for I in 0 .. Integer (Entry_Count) - 1 loop
         Match := True;
         declare
            Ent : Dir_Entry renames Root_Dir (I);
         begin
            if Name'Length <= Max_Name_Length then
               for J in Name'Range loop
                  if Name (J) /= Ent.Name (J) then Match := False; exit; end if;
               end loop;
               if Match and Name'Length < Max_Name_Length then
                  if Ent.Name (Name'Length + 1) /= ' ' then Match := False; end if;
               end if;
            else Match := False; end if;
            if Match then Idx := I; exit; end if;
         end;
      end loop;
      if Idx < 0 then
         C_Putln (Msg_NotFound'Address, Msg_NotFound'Length);
         return;
      end if;
      --  H73: free the file's data blocks in the bitmap.
      declare
         N : constant Unsigned_32 := (Root_Dir (Idx).Size + 511) / 512;
      begin
         Clear_Blocks (Root_Dir (Idx).Start_LBA, N);
      end;
      --  Remove the entry (shift the tail down; order is not significant).
      for I in Idx .. Integer (Entry_Count) - 2 loop
         Root_Dir (I) := Root_Dir (I + 1);
      end loop;
      Root_Dir (Integer (Entry_Count) - 1) :=
        (Name => (others => ' '), Start_LBA => 0, Size => 0, Checksum => 0);
      Entry_Count := Entry_Count - 1;
      --  Commit (directory + superblock, A/B atomic).
      declare
         SB : Superblock := (Magic => NVFS_Magic, Version => NVFS_Version,
                             Block_Size => 512, Root_Dir_LBA => Dir_Primary_LBA,
                             Root_Entries => Entry_Count,
                             Checksum => 0, Dir_Checksum => 0,
                             Generation => Current_Generation + 1,
                             Next_Free_LBA => Next_Free_LBA,
                             Block_Bitmap => Block_Bitmap,
                             Hmac_Key => Hmac_Key,
                             Hmac_Tag => (others => 0));
         OK : Boolean;
      begin
         Commit_Metadata (SB, OK);
         if not OK then return; end if;
      end;
      Success := True;
      C_Putln (Msg_Deleted'Address, Msg_Deleted'Length);
   end Delete_File;

   procedure Get_Entry
     (Index   : in     Unsigned_32;
      Dir_Ent :    out Dir_Entry;
      Success :    out Boolean) is
   begin
      if not Mounted or Index >= Entry_Count then
         Success := False;
         Dir_Ent := (Name => (others => ' '), Start_LBA => 0, Size => 0, Checksum => 0);
         return;
      end if;
      Dir_Ent := Root_Dir (Integer (Index)); Success := True;
   end Get_Entry;

end Schild_Schild_Fs;
