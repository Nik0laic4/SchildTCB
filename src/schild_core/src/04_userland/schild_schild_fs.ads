-- Schild TCB SchildFS — minimal A/B filesystem in the GPT free gap.
-- On-disk layout (absolute LBAs; see also mkschildfs.py):
--   LBA 2016: Superblock A (primary)    LBA 2017: Superblock B (backup)
--   LBA 2018: Root directory A          LBA 2019: Root directory B
--   LBA 2020..2047: File data (contiguous per file)
-- Each directory entry: 24-byte name + 4-byte start_lba + 4-byte size
with Interfaces; with System;

package Schild_Schild_Fs with SPARK_Mode => Off is
   use Interfaces;

   -- Superblock
   NVFS_Magic  : constant Unsigned_32 := 16#4E564653#;  -- "NVFS"
   NVFS_Version : constant Unsigned_16 := 1;

   type Superblock is record
      Magic        : Unsigned_32 := 0;
      Version      : Unsigned_16 := 0;
      Block_Size   : Unsigned_16 := 512;
      Root_Dir_LBA : Unsigned_32 := 2;
      Root_Entries : Unsigned_32 := 0;   -- number of files in root dir
      Checksum     : Unsigned_32 := 0;   -- CRC32 over bytes 0..15 (header)
      Dir_Checksum : Unsigned_32 := 0;   -- CRC32 over the root-dir block
      Generation   : Unsigned_32 := 0;   -- monotonic commit counter (A/B)
   end record
     with Size => 512 * 8;  -- must fit in one 512-byte block

   for Superblock use record
      Magic        at 0 range 0 .. 31;
      Version      at 4 range 0 .. 15;
      Block_Size   at 6 range 0 .. 15;
      Root_Dir_LBA at 8 range 0 .. 31;
      Root_Entries at 12 range 0 .. 31;
      Checksum     at 16 range 0 .. 31;
      Dir_Checksum at 20 range 0 .. 31;
      Generation   at 24 range 0 .. 31;
   end record;

   -- Directory entry (32 bytes, 16 per 512-byte block)
   Max_Name_Length : constant := 24;

   type Dir_Entry_Name is new String (1 .. Max_Name_Length);

   type Dir_Entry is record
      Name      : Dir_Entry_Name := (others => ' ');
      Start_LBA : Unsigned_32 := 0;
      Size      : Unsigned_32 := 0;
   end record
     with Size => 32 * 8;

   for Dir_Entry use record
      Name      at 0  range 0 .. 191;   -- 24 bytes
      Start_LBA at 24 range 0 .. 31;    -- 4 bytes
      Size      at 28 range 0 .. 31;    -- 4 bytes
   end record;

   type Dir_Table is array (0 .. 15) of Dir_Entry;

   -- File handle for opened files
   type File_Info is record
      Valid     : Boolean := False;
      Name      : Dir_Entry_Name := (others => ' ');
      Start_LBA : Unsigned_32 := 0;
      Size      : Unsigned_32 := 0;
      Curr_Off  : Unsigned_32 := 0;  -- current read position
   end record;

   type Unsigned_8_Array is array (Natural range <>) of Unsigned_8;

   -- API
   procedure Init (Success : out Boolean);
   -- Mount the filesystem: read superblock + root directory from NVMe

   function Is_Mounted return Boolean;

   function Is_Read_Only return Boolean;
   --  True when a CRC32 torn-write was detected at mount: the persistent layer
   --  is forced into Strict Read-Only and rejects all write transactions until
   --  a clean remount.

   procedure Open
     (Name    : in     String;
      File    :    out File_Info;
      Success :    out Boolean);
   -- Look up a file by name in the root directory

   procedure Read
     (File    : in out File_Info;
      Buf     :    out Unsigned_8_Array;
      Len     :    out Unsigned_32;
      Success :    out Boolean);
   -- Read up to Buf'Length bytes from current position

   procedure Get_Entry
     (Index   : in     Unsigned_32;
      Dir_Ent :    out Dir_Entry;
      Success :    out Boolean);
   -- Read a single directory entry by index

   procedure Create_File
     (Name    : in     String;
      Size    : in     Unsigned_32;
      Success :    out Boolean);

   procedure Write_File
     (File    : in out File_Info;
      Data    : in     Unsigned_8_Array;
      Success :    out Boolean);

end Schild_Schild_Fs;
