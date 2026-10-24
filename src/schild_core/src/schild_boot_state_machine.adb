-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_Boot_State_Machine with
  SPARK_Mode => On
is

   function Next_State (Current : Boot_State) return Boot_State is
   begin
      case Current is
         when Boot_Init =>
            return Stack_Ready;
         when Stack_Ready =>
            return Uart_Ready;
         when Uart_Ready =>
            return Early_Init;
         when Early_Init =>
            return Memory_Init;
         when Memory_Init =>
            return Kernel_Ready;
         when Kernel_Ready | Faulted =>
            return Faulted;
      end case;
   end Next_State;

   function Can_Advance (Current : Boot_State) return Boolean is
   begin
      return Current /= Kernel_Ready and then Current /= Faulted;
   end Can_Advance;

   function State_Name (Current : Boot_State) return String is
   begin
      case Current is
         when Boot_Init =>
            return "BOOT_INIT";
         when Stack_Ready =>
            return "STACK_READY";
         when Uart_Ready =>
            return "UART_READY";
         when Early_Init =>
            return "EARLY_INIT";
         when Memory_Init =>
            return "MEMORY_INIT";
         when Kernel_Ready =>
            return "KERNEL_READY";
         when Faulted =>
            return "FAULTED";
      end case;
   end State_Name;

end Schild_Boot_State_Machine;
