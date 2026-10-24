-- Schild TCB Stage 8.1D — NetServer (Ring 3) process.
-- The e1000e MMIO is mapped at 0x600000 and the DMA offset installed by the
-- Root Task.  This package exports C-callable entry points for the NetServer
-- thread (netserver.c): init and poll.
with Interfaces;
with System;

package Schild_Net_Server with SPARK_Mode => Off is
   -- Initialize the driver (Init_MMIO @ 0x600000) + the TCP/IP stack.
   -- Returns 0 on success, non-zero on failure.
   function Net_Init return Interfaces.Unsigned_32;
   pragma Export (C, Net_Init, "schild_net_init");

   -- W7: initialize the NVMe storage (Init_MMIO at the pre-mapped base set by
   -- the Root Task; 0 = storage disabled).  Returns 0 on success, non-zero on
   -- failure.
   function Net_Nvme_Init return Interfaces.Unsigned_32;
   pragma Export (C, Net_Nvme_Init, "schild_nvme_init");

   -- Poll RX once.  Returns 0 (no packet) or 1 (packet received).
   function Net_Poll return Interfaces.Unsigned_32;
   pragma Export (C, Net_Poll, "schild_net_poll");

   -- TX a frame already placed in the shared DMA frame (0x520000) by the
   -- caller (Root Task).  Len is the frame length in bytes.  Returns the first
   -- byte of the frame as an echo (shared-frame round-trip verification), or
   -- 16#FFFF_FFFF# on error.
   function Net_Tx_Shared (Len : Interfaces.Unsigned_16) return Interfaces.Unsigned_32;
   pragma Export (C, Net_Tx_Shared, "schild_net_tx_shared");

   -- Copy the next received frame into the shared DMA frame (0x520000).
   -- Returns the frame length in bytes (0 = no packet available).
   function Net_Rx_Shared return Interfaces.Unsigned_32;
   pragma Export (C, Net_Rx_Shared, "schild_net_rx_shared");

   -- Stage 9: render the global audit log into a C-provided buffer.
   -- Exported so the C bridge (schild_debug_render) can call it; the
   -- Audit_Event type is an Ada record, so formatting stays in Ada.
   procedure Render_Audit_Log
     (Buffer     : System.Address;
      Max_Len    : Natural;
      Actual_Len : out Natural)
     with Export, Convention => C, External_Name => "schild_audit_render";
end Schild_Net_Server;
