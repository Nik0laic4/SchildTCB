-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- seL4 BootInfo record — flat fields for exact C struct match
-- x86_64, MCS, CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS=500
-- (MCS inserts a `schedcontrol` SlotRegion before `untyped`, shifting the
--  latter by 16 bytes relative to the non-MCS layout.)

with Interfaces; use Interfaces;

package Schild_Sel4_BootInfo
  with SPARK_Mode => On
is
   subtype Word is Unsigned_64;
   subtype U8   is Unsigned_8;

   -- Untyped memory descriptor (packed to match C struct)
   type Untyped_Desc is record
      PAddr     : Word;
      Size_Bits : U8;
      Is_Device : U8;
      Pad1      : U8;
      Pad2      : U8;
      Pad3      : U8;
      Pad4      : U8;
      Pad5      : U8;
      Pad6      : U8;
   end record;
   pragma Pack (Untyped_Desc);

   N_UNTYPED : constant := 500;
   type Untyped_Array is array (1 .. N_UNTYPED) of Untyped_Desc
     with Convention => C;

   -- Main BootInfo struct — flat Word pairs (no nested records)
   type BootInfo is record
      Extra_Len               : Word;        -- 0x00
      Node_ID                 : Word;        -- 0x08
      Num_Nodes               : Word;        -- 0x10
      Num_IOPT_Levels         : Word;        -- 0x18
      IPC_Buffer              : Word;        -- 0x20
      Empty_Start             : Word;        -- 0x28
      Empty_End               : Word;        -- 0x30
      Shared_Frames_Start     : Word;        -- 0x38
      Shared_Frames_End       : Word;        -- 0x40
      User_Image_Frames_Start : Word;        -- 0x48
      User_Image_Frames_End   : Word;        -- 0x50
      User_Image_Paging_Start : Word;        -- 0x58
      User_Image_Paging_End   : Word;        -- 0x60
      IO_Space_Caps_Start     : Word;        -- 0x68
      IO_Space_Caps_End       : Word;        -- 0x70
      Extra_BI_Pages_Start    : Word;        -- 0x78
      Extra_BI_Pages_End      : Word;        -- 0x80
      Init_Thread_CNode_Bits  : Word;        -- 0x88
      Init_Thread_Domain      : Word;        -- 0x90
      SchedControl_Start      : Word;        -- 0x98 (MCS: sched-control caps)
      SchedControl_End        : Word;        -- 0xA0 (MCS)
      Untyped_Start           : Word;        -- 0xA8
      Untyped_End             : Word;        -- 0xB0
      Untyped_List            : Untyped_Array; -- 0xB8
   end record with Convention => C;

   -- Output helpers.  These only forward to the C console driver; they touch
   -- no SPARK-visible package state, so Global => null.  The bodies are
   -- SPARK_Mode => Off (C-console side effect), but the Global contract makes
   -- them callable from SPARK_Mode => On orchestration code.
   procedure Put_Hex (W : Word) with Global => null;
   procedure Put_Str (S : String) with Global => null;
   procedure Put_Dec (W : Word) with Global => null;
end Schild_Sel4_BootInfo;
