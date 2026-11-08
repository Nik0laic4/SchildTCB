-- Schild TCB SchildFS — minimal A/B filesystem in the GPT free gap.
-- On-disk layout (absolute LBAs; see also mkschildfs.py):
--   LBA 2016: Superblock A (primary)    LBA 2017: Superblock B (backup)
--   LBA 2018: Root directory A          LBA 2019: Root directory B
--   LBA 2020..2047: File data (contiguous per file)
-- Each directory entry: 24-byte name + 4-byte start_lba + 4-byte size
-- The on-disk types (Superblock / Dir_Entry) and their parsers live in
-- Schild_Fs_Core (SPARK_Mode => On, audit H63); this package is the stateful
-- I/O layer.
with Interfaces; with System;
with Schild_Fs_Core;

package Schild_Schild_Fs with SPARK_Mode => Off is
   use Interfaces; use Schild_Fs_Core;

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

   procedure Delete_File
     (Name    : in     String;
      Success :    out Boolean);
   --  H73: remove a file by name and free its data blocks in the block bitmap
   --  (first-fit allocator reuses freed blocks). Fails if the name is unknown
   --  or the FS is read-only.

end Schild_Schild_Fs;
