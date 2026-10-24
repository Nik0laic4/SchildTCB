-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- Schild TCB Stage 7.9: Network Stack Dispatcher
-- Polls e1000e RX, dispatches to ARP/IPv4/TCP/HTTP.

package Schild_Net_Stack with SPARK_Mode => Off is
   procedure Init;
   -- Persist the captured boot log (schild_log_buf / schild_log_len) to NVMe
   -- LBA 2000+. Exposed so the kernel can flush early, before anything that
   -- might hang, guaranteeing an observable boot log on the T580 (no serial/VGA).
   procedure Flush_Log_To_Nvme;
   procedure Run_Loop;
   -- Poll RX once and dispatch a received frame (single-shot, non-blocking).
   -- Returns True if a frame was received and processed.
   function Poll_And_Process return Boolean;
end Schild_Net_Stack;
