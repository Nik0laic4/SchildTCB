-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for Schild_IPC_Ports (deterministic IPC).
-- Verifies sampling-port overwrite semantics and queuing-port FIFO + bounds.
-- Host-side program: run via run_ipc_kat.sh.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Schild_IPC_Ports; use Schild_IPC_Ports;

procedure Ipc_KAT is
   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      if Cond then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   S  : Sampling_Port;
   Q  : Queuing_Port;
   E  : Element;
   V  : Boolean;
   Ok : Boolean;

begin
   -- ---- Sampling port ----
   Sample_Write (S, 42);
   Sample_Read (S, E, V);
   Check ("sampling write/read -> 42", V and then E = 42);
   Sample_Read (S, E, V);
   Check ("sampling fresh cleared", not V);

   Sample_Write (S, 7);
   Sample_Write (S, 9);
   Sample_Read (S, E, V);
   Check ("sampling overwrite -> 9", V and then E = 9);

   -- ---- Queuing port ----
   declare
      Ok1, Ok2, Ok3 : Boolean;
   begin
      Queue_Send (Q, 1, Ok1);
      Queue_Send (Q, 2, Ok2);
      Queue_Send (Q, 3, Ok3);
      Check ("queue enqueue x3", Ok1 and then Ok2 and then Ok3);
   end;
   Check ("queue count = 3", Queue_Count (Q) = 3);

   Queue_Receive (Q, E, Ok);
   Check ("queue dequeue -> 1 (FIFO)", Ok and then E = 1);
   Queue_Receive (Q, E, Ok);
   Check ("queue dequeue -> 2", Ok and then E = 2);
   Queue_Receive (Q, E, Ok);
   Check ("queue dequeue -> 3", Ok and then E = 3);
   Check ("queue empty", Queue_Empty (Q));

   Queue_Receive (Q, E, Ok);
   Check ("queue receive on empty -> false", not Ok);

   -- Fill to capacity (deterministic bounded behaviour).
   for I in 1 .. Max_Capacity loop
      Queue_Send (Q, Element (I), Ok);
   end loop;
   Check ("queue full after 64", Queue_Full (Q));
   Queue_Send (Q, 999, Ok);
   Check ("queue send on full -> false", not Ok);

   -- Drain back to empty.
   for I in 1 .. Max_Capacity loop
      Queue_Receive (Q, E, Ok);
   end loop;
   Check ("queue drained -> empty", Queue_Empty (Q));

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("IPC KAT: ALL PASS");
   else
      Ada.Text_IO.Put_Line
        ("IPC KAT: " & Natural'Image (Failures) & " FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Ipc_KAT;
