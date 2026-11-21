-- Schild TCB — FS Daemon (Ring 3) process spec.
-- Audit H65: FS body moves out of the root task VSpace into a daemon thread.
-- Pattern: same as Schild_Net_Server — Ada export, C dispatch loop (fs_daemon.c).
--
-- IPC contract (MR layout, sync with fs_daemon.c):
--   MR[0] = op, MR[1..3] = args
--   Reply MR[0] = status (0=ok), MR[1..3] = result
--   Large data (name, bytes, dir entry) via shared DMA frame @ 0x520000.
--
-- Ops:
--   0 Init, 1 Open, 2 Read, 3 Write, 4 Create, 5 Append, 6 Get_Entry,
--   7 Is_Mounted, 8 Is_Read_Only, 9 Delete, 99 fault-injection (test)
with Interfaces;
with Schild_Schild_Fs;
with Schild_MLS_Policy;

use type Interfaces.Unsigned_32;

package Schild_Fs_Server with SPARK_Mode => Off is

   -- Op codes (MR[0]) — синхронизировано с fs_daemon.c
   Op_Init        : constant := 0;
   Op_Open        : constant := 1;
   Op_Read        : constant := 2;
   Op_Write       : constant := 3;
   Op_Create      : constant := 4;
   Op_Append      : constant := 5;
   Op_Get_Entry   : constant := 6;
   Op_Is_Mounted  : constant := 7;
   Op_Is_Read_Only: constant := 8;
   Op_Delete      : constant := 9;
   Op_Fault_Test  : constant := 99;

   -- M19: single source of truth for the per-op byte-buffer size (the shared
   -- DMA frame chunk copied per Read/Write/Append). The body clamps Len to it.
   Fs_Buffer_Size : constant := 2048;
   -- Fs_Append uses the full 4 KiB shared frame (4096), not the 2048 chunk.
   Fs_Append_Buffer_Size : constant := 4096;

   -- Status codes (Reply MR[0])
   St_Ok          : constant := 0;
   St_Not_Mounted : constant := 1;
   St_No_File     : constant := 2;
   St_Io_Error    : constant := 3;
   St_Bad_Op      : constant := 4;
   St_Read_Only   : constant := 5;
   St_No_Space    : constant := 6;
   St_Denied      : constant := 7;   -- R23: MLS gate denied

   -- H65: initialize NVMe MMIO + SchildFS. Returns St_Ok on success.
   -- Root task calls this once at boot (after Launch_FS_Daemon).
   function Fs_Init return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Init, "schild_fs_init");

   -- Open a file by name (name bytes in shared frame @ 0x520000).
   -- Mode: 0 = read (Can_Read), 1 = write (Can_Write) — R23.
   -- Reply: handle (index into Root_Dir), size.
   function Fs_Open
     (Name_Len : Interfaces.Unsigned_32;
      Mode     : Interfaces.Unsigned_32;
      Handle   : out Interfaces.Unsigned_32;
      Size     : out Interfaces.Unsigned_32) return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Open, "schild_fs_open");

   -- Read up to Len bytes at Offset, copy into shared frame.
   -- M19: Len is bounded by the shared-frame size (2048); the body clamps as
   -- the runtime guard for the C caller (this package is Off, so the Pre is
   -- documentation, not a proved contract).
   -- Reply: actual_len (0 = EOF).
   function Fs_Read
     (Handle    : Interfaces.Unsigned_32;
      Offset    : Interfaces.Unsigned_32;
      Len       : Interfaces.Unsigned_32;
      Actual    : out Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   with Pre => Len <= Fs_Buffer_Size;
   pragma Export (C, Fs_Read, "schild_fs_read");

   -- Write Len bytes from shared frame at Offset.
   -- M19: Len bounded by the shared-frame size (2048); body clamps (see Fs_Read).
   -- Reply: new_offset (Offset + Len on success).
   function Fs_Write
     (Handle    : Interfaces.Unsigned_32;
      Offset    : Interfaces.Unsigned_32;
      Len       : Interfaces.Unsigned_32;
      New_Off   : out Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   with Pre => Len <= Fs_Buffer_Size;
   pragma Export (C, Fs_Write, "schild_fs_write");

   -- Create a file (name in shared frame, name_len). Size pre-allocates.
   -- Level: R23 clearance (0..4) for the new file; Owner = caller role.
   function Fs_Create
     (Name_Len  : Interfaces.Unsigned_32;
      Size      : Interfaces.Unsigned_32;
      Level     : Interfaces.Unsigned_32;
      Handle    : out Interfaces.Unsigned_32) return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Create, "schild_fs_create");

   -- Append Len bytes from shared frame at end of file (H72=Б).
   -- M19: Len bounded by the full shared-frame size (4096); body clamps.
   -- Reply: new_size.
   function Fs_Append
     (Name_Len  : Interfaces.Unsigned_32;
      Len       : Interfaces.Unsigned_32;
      New_Size  : out Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   with Pre => Len <= Fs_Append_Buffer_Size;
   pragma Export (C, Fs_Append, "schild_fs_append");

   -- Delete a file by name (name in shared frame, name_len). Frees its data
   -- blocks in the bitmap (H73). Reply: status.
   function Fs_Delete
     (Name_Len  : Interfaces.Unsigned_32) return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Delete, "schild_fs_delete");

   function Fs_Get_Entry
     (Index     : Interfaces.Unsigned_32) return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Get_Entry, "schild_fs_get_entry");

   function Fs_Is_Mounted return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Is_Mounted, "schild_fs_is_mounted");

   function Fs_Is_Read_Only return Interfaces.Unsigned_32;
   pragma Export (C, Fs_Is_Read_Only, "schild_fs_is_read_only");

end Schild_Fs_Server;
