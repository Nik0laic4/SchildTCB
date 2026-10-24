-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package Schild_Early_Init with
  SPARK_Mode => On
is

   type Memory_Block is record
      Base : Integer;
      Size : Integer;
   end record;

   function Init_Memory_Block (Base : Integer; Size : Integer) return Memory_Block;

   function Is_Valid_Block (Block : Memory_Block) return Boolean;

end Schild_Early_Init;
