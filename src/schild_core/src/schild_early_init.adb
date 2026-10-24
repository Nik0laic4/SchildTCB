-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_Early_Init with
  SPARK_Mode => On
is

   function Init_Memory_Block (Base : Integer; Size : Integer) return Memory_Block is
   begin
      return (Base => Base, Size => Size);
   end Init_Memory_Block;

   function Is_Valid_Block (Block : Memory_Block) return Boolean is
   begin
      return Block.Size > 0;
   end Is_Valid_Block;

end Schild_Early_Init;
