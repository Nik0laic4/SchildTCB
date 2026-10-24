-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

--  Schild TCB - global kernel state.
--  Holds the process table shared across the kernel entry point.

with Schild_Process_Manager;

package Schild_Kernel_State with
  SPARK_Mode => Off
is
   pragma Elaborate_Body;

   --  The global process table.
   Proc_Table : Schild_Process_Manager.Process_Table;
end Schild_Kernel_State;
