-- Schild TCB — provable SchildFS on-disk parsing core (P3 input path).
--
-- Extracted from Schild_Schild_Fs so the superblock / directory parsers can
-- be proved at SPARK Level 4. The on-disk metadata is an untrusted DMA input
-- (threat model T15 / audit H63): Bytes_To_Superblock, Bytes_To_Dir_Entry and
-- CRC32 must be memory-safe for any 512-byte buffer the NVMe driver returns.
-- Constrained Block_Buf avoids the prover limitation of unconstrained arrays.

with Interfaces; use Interfaces;
with Schild_HMAC_SHA256;

package Schild_Fs_Core with SPARK_Mode => On is

   -- 512-byte block (one NVMe sector).
   type Block_Buf is array (0 .. 511) of Unsigned_8;

   NVFS_Magic   : constant Unsigned_32 := 16#4E564653#;  -- "NVFS"
   NVFS_Version : constant Unsigned_16 := 4;             -- H62: + per-file CRC

   -- Superblock (512 bytes; see also mkschildfs.py).
   type Superblock is record
      Magic         : Unsigned_32 := 0;
      Version       : Unsigned_16 := 0;
      Block_Size    : Unsigned_16 := 512;
      Root_Dir_LBA  : Unsigned_32 := 2;
      Root_Entries  : Unsigned_32 := 0;   -- number of files in root dir
      Checksum      : Unsigned_32 := 0;   -- CRC32 over bytes 0..15 (header)
      Dir_Checksum  : Unsigned_32 := 0;   -- CRC32 over the root-dir block
      Generation    : Unsigned_32 := 0;   -- monotonic commit counter (A/B)
      Next_Free_LBA : Unsigned_32 := 0;   -- audit H74: persisted allocator state
      Block_Bitmap  : Unsigned_32 := 0;   -- audit H60: used-block bitmap
      Hmac_Key      : Schild_HMAC_SHA256.SHA256_Hash := (others => 0);  -- H61
      Hmac_Tag      : Schild_HMAC_SHA256.SHA256_Hash := (others => 0);  -- H61
   end record
     with Size => 512 * 8;  -- must fit in one 512-byte block

   for Superblock use record
      Magic         at 0 range 0 .. 31;
      Version       at 4 range 0 .. 15;
      Block_Size    at 6 range 0 .. 15;
      Root_Dir_LBA  at 8 range 0 .. 31;
      Root_Entries  at 12 range 0 .. 31;
      Checksum      at 16 range 0 .. 31;
      Dir_Checksum  at 20 range 0 .. 31;
      Generation    at 24 range 0 .. 31;
      Next_Free_LBA at 28 range 0 .. 31;
      Block_Bitmap  at 32 range 0 .. 31;
      Hmac_Key      at 448 range 0 .. 255;
      Hmac_Tag      at 480 range 0 .. 255;
   end record;

   -- Directory entry (36 bytes, 14 per 512-byte block).
   Max_Name_Length : constant := 24;

   type Dir_Entry_Name is new String (1 .. Max_Name_Length);

   type Dir_Entry is record
      Name      : Dir_Entry_Name := (others => ' ');
      Start_LBA : Unsigned_32 := 0;
      Size      : Unsigned_32 := 0;
      Checksum  : Unsigned_32 := 0;   -- H62: CRC32 over the file's data bytes
   end record
     with Size => 36 * 8;

   for Dir_Entry use record
      Name      at 0  range 0 .. 191;   -- 24 bytes
      Start_LBA at 24 range 0 .. 31;    -- 4 bytes
      Size      at 28 range 0 .. 31;    -- 4 bytes
      Checksum  at 32 range 0 .. 31;    -- 4 bytes (H62)
   end record;

   -- CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320) over the first Len
   -- bytes of Data. Detects torn/corrupted metadata blocks.
   function CRC32 (Data : Block_Buf; Len : Natural) return Unsigned_32
     with Pre => Len <= 512;

   -- Parse the superblock header (bytes 0..35) from a raw block.
   procedure Bytes_To_Superblock (Raw : Block_Buf; SB : out Superblock);

   -- Serialize the superblock header into a raw block (bytes 0..35, rest 0).
   procedure Superblock_To_Bytes (SB : Superblock; Raw : out Block_Buf)
     with Relaxed_Initialization => Raw;

   -- Parse one 36-byte directory entry at offset Off.
   procedure Bytes_To_Dir_Entry
     (Raw : Block_Buf; Off : Natural; Ent : out Dir_Entry)
     with Pre => Off <= 512 - 36;

   -- Serialize one 36-byte directory entry at offset Off.
   procedure Dir_Entry_To_Bytes
     (Ent : Dir_Entry; Raw : in out Block_Buf; Off : Natural)
     with Pre => Off <= 512 - 36,
          Relaxed_Initialization => Raw;

end Schild_Fs_Core;
