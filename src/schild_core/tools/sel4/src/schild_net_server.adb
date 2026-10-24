-- Schild TCB Stage 8.1D — NetServer (Ring 3) process body.
with System;
with Interfaces;
with Schild_E1000e;
with Schild_Net_Stack;
with Schild_Nvme;
with Schild_Schild_Fs;
with Schild_Audit_Logger; use Schild_Audit_Logger;
with Schild_Config_Daemon; use Schild_Config_Daemon;

package body Schild_Net_Server with SPARK_Mode => Off is
   use Interfaces;

   -- Shared-frame copy helpers (linked from schild_net_runtime.c).
   procedure Shared_Copy_From (Dst : System.Address; Len : Unsigned_32);
   pragma Import (C, Shared_Copy_From, "schild_shared_copy_from");
   procedure Shared_Copy_To (Src : System.Address; Len : Unsigned_32);
   pragma Import (C, Shared_Copy_To, "schild_shared_copy_to");

   function Net_Init return Unsigned_32 is
   begin
      -- MMIO window at 0x600000 (mapped by Root Task via X86PageMap).
      Schild_E1000e.Init_MMIO (16#600000#);
      if not Schild_E1000e.Is_Ready then
         return 1;
      end if;
      Schild_Net_Stack.Init;
      -- W7: initialize the NVMe storage (no-op if the Root Task mapped none).
      if Net_Nvme_Init /= 0 then
         return 2;
      end if;
      return 0;
   end Net_Init;

   function C_Nvme_Get_Mmio return Unsigned_64;
   pragma Import (C, C_Nvme_Get_Mmio, "schild_nvme_get_mmio");

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   function Net_Nvme_Init return Unsigned_32 is
      MMIO_Base : Unsigned_64;
      FS_OK  : Boolean;
      F      : Schild_Schild_Fs.File_Info;
      OK     : Boolean;
      Buf    : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31);
      Len    : Unsigned_32;
      Msg_FS1 : constant String := "[NVFS] Init OK";
      Msg_FS2 : constant String := "[NVFS] Create test.txt OK";
      Msg_FS3 : constant String := "[NVFS] Write OK";
      Msg_FS4 : constant String := "[NVFS] Read-back VERIFY OK";
   begin
      MMIO_Base := C_Nvme_Get_Mmio;
      if MMIO_Base = 0 then
         return 0;  -- storage disabled (no NVMe mapped by the Root Task)
      end if;
      Schild_Nvme.Init_MMIO (MMIO_Base);
      if not Schild_Nvme.Is_Ready then
         return 1;
      end if;

      -- SchildFS write-path test (Create -> Open -> Write -> Read -> Verify).
      Schild_Schild_Fs.Init (FS_OK);
      if FS_OK then
         C_Putln (Msg_FS1'Address, Msg_FS1'Length);
         Schild_Schild_Fs.Create_File ("test.txt", 512, OK);
         if OK then
            C_Putln (Msg_FS2'Address, Msg_FS2'Length);
            Schild_Schild_Fs.Open ("test.txt", F, OK);
            if OK then
               declare
                  Data : constant Schild_Schild_Fs.Unsigned_8_Array (0 .. 511) :=
                    (0=>78,1=>101,2=>118,3=>97,4=>79,5=>83,
                     6=>32,7=>119,8=>114,9=>105,10=>116,11=>101,
                     12=>115,13=>116,14=>33,15=>10, others=> 0);
               begin
                  Schild_Schild_Fs.Write_File (F, Data, OK);
                  if OK then
                     C_Putln (Msg_FS3'Address, Msg_FS3'Length);
                     F.Curr_Off := 0;
                     Schild_Schild_Fs.Read (F, Buf, Len, OK);
                     if OK and then Len >= 2 and then Buf (0) = 78 and then Buf (1) = 101 then
                        C_Putln (Msg_FS4'Address, Msg_FS4'Length);
                     end if;
                  end if;
               end;
            end if;
         end if;
      end if;
      return 0;
   end Net_Nvme_Init;

   function Net_Poll return Unsigned_32 is
   begin
      -- Clear the device-level interrupt (ICR read-to-clear) before dispatching,
      -- so the Root Task can safely ack the seL4 IRQ afterwards.
      Schild_E1000e.Clear_IRQ;
      -- Full packet dispatch (EtherType -> ARP/IPv4/ICMP/TCP/HTTP) now runs
      -- inside NetServer; previously the received frame was discarded here.
      if Schild_Net_Stack.Poll_And_Process then
         return 1;
      else
         return 0;
      end if;
   end Net_Poll;

   function Net_Tx_Shared (Len : Unsigned_16) return Unsigned_32 is
      Buf : Schild_E1000e.Unsigned_8_Array (0 .. 2047);
   begin
      if Len = 0 or Len > 2048 then
         return 16#FFFF_FFFF#;
      end if;
      -- Read the frame the Root Task placed in the shared DMA frame.
      Shared_Copy_From (Buf'Address, Unsigned_32 (Len));
      Schild_E1000e.Send_Packet (Buf, Len);
      -- Echo the first byte: proves the shared frame round-tripped.
      return Unsigned_32 (Buf (0));
   end Net_Tx_Shared;

   function Net_Rx_Shared return Unsigned_32 is
      Buf : Schild_E1000e.Unsigned_8_Array (0 .. 2047);
      Len : Unsigned_16;
   begin
      if not Schild_E1000e.Poll_Rx (Buf, Len) then
         return 0;
      end if;
      -- Copy the received frame into the shared DMA frame for the Root Task.
      Shared_Copy_To (Buf'Address, Unsigned_32 (Len));
      return Unsigned_32 (Len);
   end Net_Rx_Shared;

   ----------------------------------------------------------------------------
   -- Stage 9: audit-log renderer exported to C (schild_audit_render).
   -- Reads the global audit-logger ring buffer via Buffered_Events/Read_Event
   -- and formats each Audit_Event as one text line. The public-profile logger
   -- is a stub (0 buffered events), so /debug honestly reports "0 buffered".
   ----------------------------------------------------------------------------
   Global_Logger : Audit_Logger;
   Global_Init   : Boolean := False;

   procedure Render_Audit_Log
     (Buffer     : System.Address;
      Max_Len    : Natural;
      Actual_Len : out Natural)
   is
      Buf : array (0 .. 4095) of Unsigned_8;
      for Buf'Address use Buffer;
      Pos : Integer := 0;
      Cap : constant Integer := (if Max_Len > 4096 then 4096 else Max_Len);
      LF  : constant String := (1 => ASCII.LF);

      procedure Put (S : String) is
      begin
         for I in S'Range loop
            exit when Pos >= Cap;
            Buf (Pos) := Character'Pos (S (I));
            Pos := Pos + 1;
         end loop;
      end Put;

      procedure Put_U64 (V : Unsigned_64) is
         Tmp : array (0 .. 19) of Unsigned_8;
         TP  : Integer := 19;
         Val : Unsigned_64 := V;
      begin
         if Val = 0 then
            Tmp (19) := 48;
            TP := 19;
         else
            while Val > 0 loop
               Tmp (TP) := 48 + Unsigned_8 (Val rem 10);
               TP := TP - 1;
               Val := Val / 10;
            end loop;
         end if;
         for J in TP + 1 .. 19 loop
            exit when Pos >= Cap;
            Buf (Pos) := Tmp (J);
            Pos := Pos + 1;
         end loop;
      end Put_U64;

      procedure Put_Severity (S : Audit_Level) is
      begin
         case S is
            when Emergency => Put ("EMERGENCY");
            when Alert     => Put ("ALERT");
            when Critical  => Put ("CRITICAL");
            when Error     => Put ("ERROR");
            when Warning   => Put ("WARNING");
            when Notice    => Put ("NOTICE");
            when Info      => Put ("INFO");
            when Debug     => Put ("DEBUG");
         end case;
      end Put_Severity;

      procedure Put_Domain (D : Config_Domain) is
      begin
         case D is
            when Domain_Security => Put ("SECURITY");
            when Domain_Network  => Put ("NETWORK");
            when Domain_Boot     => Put ("BOOT");
         end case;
      end Put_Domain;

      Ev : Audit_Event;
   begin
      Actual_Len := 0;
      if Cap <= 0 then
         return;
      end if;

      if not Global_Init then
         Initialize (Global_Logger, Warning);
         Global_Init := True;
      end if;

      Put ("Events buffered: ");
      Put_U64 (Unsigned_64 (Buffered_Events (Global_Logger)));
      Put (LF);

      while Buffered_Events (Global_Logger) > 0 loop
         Read_Event (Global_Logger, Ev);
         Put ("[ts=");
         Put_U64 (Ev.Timestamp);
         Put ("] ");
         Put_Severity (Ev.Severity);
         Put (" ");
         Put_Domain (Ev.Domain);
         Put (" ev=");
         Put_U64 (Ev.Event_ID);
         Put (" detail=");
         Put_U64 (Ev.Detail);
         Put (LF);
      end loop;

      Actual_Len := Natural (Pos);
   end Render_Audit_Log;

end Schild_Net_Server;
