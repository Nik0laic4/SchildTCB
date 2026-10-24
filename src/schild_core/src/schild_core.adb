-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Schild_Boot_Runtime;
with Schild_Boot_State_Machine;
with Schild_Early_Init;
with Schild_Uart_Driver;

use type Schild_Boot_Runtime.Boot_Status;

package body Schild_Core with
  SPARK_Mode => On
is

   procedure Emit_Boot_Trace (State : Schild_Boot_State_Machine.Boot_State; Message : String) is
   begin
      Schild_Uart_Driver.Put_String ("Schild TCB[");
      Schild_Uart_Driver.Put_String (Schild_Boot_State_Machine.State_Name (State));
      Schild_Uart_Driver.Put_String ("] ");
      Schild_Uart_Driver.Put_Line (Message);
   end Emit_Boot_Trace;

   procedure System_Main_Entry is
      Current_State : Schild_Boot_State_Machine.Boot_State := Schild_Boot_State_Machine.Boot_Init;
   begin
      Emit_Boot_Trace (Current_State, "boot sequence started");

      while Schild_Boot_State_Machine.Can_Advance (Current_State) loop
         declare
            Next_State : constant Schild_Boot_State_Machine.Boot_State :=
              Schild_Boot_State_Machine.Next_State (Current_State);
            Memory_Block : constant Schild_Early_Init.Memory_Block :=
              Schild_Early_Init.Init_Memory_Block (16#100000#, 16#1000#);
         begin
            Current_State := Next_State;
            if Schild_Early_Init.Is_Valid_Block (Memory_Block) then
               Emit_Boot_Trace (Current_State, "state advanced and memory block initialized");
            else
               Schild_Boot_Runtime.Report_Failure ("memory block validation failed");
               Schild_Boot_Runtime.Enter_Recovery_Mode ("entering fallback mode");
               Emit_Boot_Trace (Current_State, "state advanced with invalid memory block");
               exit;
            end if;
         end;
      end loop;

      if Schild_Boot_Runtime.Current_Status = Schild_Boot_Runtime.Recovering then
         Schild_Boot_Runtime.Mark_Recovery_Complete;
         Emit_Boot_Trace (Current_State, "recovery complete");
      else
         Schild_Boot_Runtime.Mark_Stable;
         Emit_Boot_Trace (Current_State, "Ada kernel core ready");
      end if;
   end System_Main_Entry;

end Schild_Core;
