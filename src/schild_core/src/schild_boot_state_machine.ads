-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package Schild_Boot_State_Machine with
  SPARK_Mode => On
is

   type Boot_State is (Boot_Init, Stack_Ready, Uart_Ready, Early_Init, Memory_Init, Kernel_Ready, Faulted);

   function Next_State (Current : Boot_State) return Boot_State;

   function Can_Advance (Current : Boot_State) return Boolean;

   function State_Name (Current : Boot_State) return String;

end Schild_Boot_State_Machine;
