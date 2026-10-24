-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_IPC_Ports with SPARK_Mode => On is

   procedure Sample_Write (P : in out Sampling_Port; E : Element) is
   begin
      P.Data  := E;
      P.Fresh := True;
   end Sample_Write;

   procedure Sample_Read (P : in out Sampling_Port; E : out Element; Valid : out Boolean) is
   begin
      E      := P.Data;
      Valid  := P.Fresh;
      P.Fresh := False;
   end Sample_Read;

   procedure Queue_Send (P : in out Queuing_Port; E : Element; Success : out Boolean) is
   begin
      if P.Count >= Max_Capacity then
         Success := False;
         return;
      end if;
      P.Buf (P.Tail) := E;
      P.Tail  := (P.Tail + 1) mod Max_Capacity;
      P.Count := P.Count + 1;
      Success := True;
   end Queue_Send;

   procedure Queue_Receive (P : in out Queuing_Port; E : out Element; Success : out Boolean) is
   begin
      if P.Count = 0 then
         E := 0;
         Success := False;
         return;
      end if;
      E      := P.Buf (P.Head);
      P.Head  := (P.Head + 1) mod Max_Capacity;
      P.Count := P.Count - 1;
      Success := True;
   end Queue_Receive;

   function Queue_Count (P : Queuing_Port) return Natural is (P.Count);

end Schild_IPC_Ports;
