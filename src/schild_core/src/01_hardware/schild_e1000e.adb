-- Schild TCB e1000e Driver — TX + RX rings, packet send
with System; with System.Machine_Code; with Interfaces;

with Schild_Uart_Driver; with Schild_Pci_Scanner; with Schild_Nvme;

package body Schild_E1000e with SPARK_Mode => Off is
   use Interfaces;

   -- C helpers for address conversion (bare-metal: no System.Storage_Elements)
   function C_Addr (A : System.Address) return Unsigned_64;
   pragma Import (C, C_Addr, "schild_ptr_to_u64");
   -- DMA physical address (Ring 0 = identity-mapped; Ring 3 = virtual + offset)
   function C_Dma_Phys (A : System.Address) return Unsigned_64;
   pragma Import (C, C_Dma_Phys, "schild_dma_phys");
   procedure C_Map_MMIO (Phys_Addr : Unsigned_64);
   pragma Import (C, C_Map_MMIO, "schild_map_mmio_2mb");
   procedure C_Set_MMIO (MMIO_Addr : Unsigned_64);
   pragma Import (C, C_Set_MMIO, "schild_e1000e_set_mmio");
   procedure C_Ioapic_Unmask (Pin, Vector : Unsigned_32);
   pragma Import (C, C_Ioapic_Unmask, "schild_ioapic_unmask_pin");
   procedure C_Log_Hex32 (V : Unsigned_32);
   pragma Import (C, C_Log_Hex32, "schild_log_hex32");
   -- DMA cache coherence for real hardware (ThinkPad T580)
   procedure C_WbInvd;
   pragma Import (C, C_WbInvd, "schild_wbinvd");
   procedure C_ClFlush (Addr : System.Address);
   pragma Import (C, C_ClFlush, "schild_clflush");
   function C_Rdtsc return Unsigned_64;
   pragma Import (C, C_Rdtsc, "schild_rdtsc");


   MMIO  : Unsigned_64 := 0;
   Ready : Boolean := False;
   Cached_MAC : Mac_Addr := (others => 0);

   Msg_TX_TO : constant String := "[E1000E] TX timeout";

   NUM_DESC : constant := 8;
   TX_BUF_SIZE : constant := 2048;
   RX_BUF_SIZE : constant := 2048;

   -- TX descriptor (16 bytes, e1000e legacy format)
   type Tx_Desc is record
      Addr   : Unsigned_64 := 0;
      Len    : Unsigned_16 := 0;
      Cso    : Unsigned_8  := 0;   -- byte 10: checksum offset
      Cmd    : Unsigned_8  := 0;   -- byte 11: command (EOP/IFCS/RS)
      Status : Unsigned_8  := 0;
      Css    : Unsigned_8  := 0;
      Spec   : Unsigned_16 := 0;
   end record;
   --  e1000 requires the descriptor ring base to be 16-byte aligned (the
   --  default Unsigned_64 alignment is only 8).
   for Tx_Desc'Alignment use 16;

   Tx_Ring : array (0 .. NUM_DESC - 1) of Tx_Desc;
   Tx_Buf  : array (0 .. NUM_DESC - 1, 0 .. TX_BUF_SIZE - 1) of Unsigned_8;
   Tx_Idx  : Unsigned_32 := 0;

   -- RX descriptor ring + buffers (one buffer per descriptor)
   Rx_Ring : array (0 .. NUM_DESC - 1) of Tx_Desc;
   Rx_Buf  : array (0 .. NUM_DESC - 1, 0 .. RX_BUF_SIZE - 1) of Unsigned_8;
   Rx_Idx  : Unsigned_32 := 0;

   procedure Mmio_Write (Off, Val : Unsigned_32) is
      A : constant Unsigned_64 := MMIO + Unsigned_64 (Off);
   begin
      System.Machine_Code.Asm ("movl %0, (%1)",
        Inputs => (Unsigned_32'Asm_Input ("r", Val), Unsigned_64'Asm_Input ("r", A)),
        Volatile => True);
   end;

   function Mmio_Read (Off : Unsigned_32) return Unsigned_32 is
      A : constant Unsigned_64 := MMIO + Unsigned_64 (Off); V : Unsigned_32;
   begin
      System.Machine_Code.Asm ("movl (%1), %0",
        Outputs => Unsigned_32'Asm_Output ("=r", V),
        Inputs  => Unsigned_64'Asm_Input ("r", A), Volatile => True);
      return V;
   end;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   procedure Poll_Status is
      X : Unsigned_32 := Mmio_Read (16#0008#);  -- STATUS (MMIO read)
   begin
      null;
   end Poll_Status;



   -- Shared init: reset the device, program TX/RX rings and enable the MAC.
   -- Ring 3 (NetServer) path: MMIO is already mapped by the Root Task via
   -- X86PageMap (vaddr 0x600000). No PCI scan (port I/O), no
   -- schild_map_mmio_2mb (page-table edit), no IOAPIC — all Ring 0 only.
   procedure Init_MMIO (MMIO_VAddr : Unsigned_64) is
      C : Unsigned_32;
      Msg_Mapped : constant String := "[E1000E] MMIO base set (pre-mapped vaddr)";
   begin
      MMIO := MMIO_VAddr;
      C_Putln (Msg_Mapped'Address, Msg_Mapped'Length);
      Schild_Nvme.Flush_Log_To_Nvme;

      -- Device reset sequence
      C := Mmio_Read (16#0000#);
      declare
         M : constant String := "[E1000E] reset: read OK";
      begin
         C_Putln (M'Address, M'Length);
      end;
      Schild_Nvme.Flush_Log_To_Nvme;
      Mmio_Write (16#0000#, C or 16#04000000#);
      declare
         M : constant String := "[E1000E] reset: write OK";
      begin
         C_Putln (M'Address, M'Length);
      end;
      Schild_Nvme.Flush_Log_To_Nvme;
      for I in 1..100000 loop null; end loop;

      -- Wait for reset completion (CTRL.RST clears; STATUS.FD is not the reset bit)
      for I in 1..1000 loop
         exit when (Mmio_Read (16#0000#) and 16#04000000#) = 0;
         for J in 1..1000 loop null; end loop;
      end loop;
      Schild_Nvme.Flush_Log_To_Nvme;

      -- Wait for the EEPROM auto-read to complete (EEC.EE_DONE bit 1): the
      -- device will not transmit until the EEPROM (MAC/config) has loaded.
      for I in 1 .. 1000 loop
         exit when (Mmio_Read (16#0014#) and 16#00000002#) /= 0;
         for J in 1 .. 1000 loop null; end loop;
      end loop;
      Schild_Nvme.Flush_Log_To_Nvme;

      -- Set SLU + clear FRCSPD/FRCDPX (allow auto-negotiation), matching Linux
      -- e1000_setup_copper_link_ich8lan.
      declare
         Ctrl1 : Unsigned_32 := Mmio_Read (16#0000#);
      begin
         Ctrl1 := (Ctrl1 or 16#00000040#) and not (16#00000800# or 16#00001000#);
         Mmio_Write (16#0000#, Ctrl1);
      end;

      -- KMRN config (Linux e1000_setup_copper_link_ich8lan): the kumeran
      -- (MAC-PHY) interface timeout must be maxed out, otherwise the MAC times
      -- out polling the PHY and the link stays stuck at 10 Mbps (SPEED=0).
      --   KMRNCTRLSTA (0x34) write: (offset << 16) | data.
      --   KMRN_TIMEOUTS (0x4) = 0xFFFF.
      Mmio_Write (16#0034#, 16#0004FFFF#);
      --   KMRN_INBAND_PARAM (0x9) |= 0x3F.
      declare
         Param : Unsigned_32;
      begin
         Mmio_Write (16#0034#, 16#00290000#);  -- read cmd: (0x9<<16) | REN(0x200000)
         declare X : Unsigned_32 := Mmio_Read (16#0000#); begin null; end;  -- ~2us
         Param := Mmio_Read (16#0034#) and 16#FFFF#;
         Param := Param or 16#3F#;
         Mmio_Write (16#0034#, 16#00090000# or Param);  -- write cmd: (0x9<<16) | data
      end;

      -- PHY reset pulse (Linux e1000e_phy_hw_reset_generic): explicit reset to
      -- start auto-negotiation.
      declare
         Ctrl0 : Unsigned_32 := Mmio_Read (16#0000#);
      begin
         Mmio_Write (16#0000#, Ctrl0 or 16#80000000#);  -- assert PHY_RST (bit 31)
         declare X : Unsigned_32 := Mmio_Read (16#0000#); begin null; end;  -- delay
         Mmio_Write (16#0000#, Ctrl0);                   -- deassert PHY_RST
      end;

      -- Wait for link-up (STATUS.LU bit 1) AND DMoff exit (PCIM_STATE bit 30
      -- clears).  LU alone is forced by SLU and is not proof the DMA engine is
      -- alive; DMoff keeps DMA off so RX descriptors never get written.
      declare
         use type Interfaces.Unsigned_64;
         T0 : constant Unsigned_64 := C_Rdtsc;
         St : Unsigned_32;
      begin
         loop
            St := Mmio_Read (16#0008#);
            exit when (St and 16#00000002#) /= 0
              and then (St and 16#40000000#) = 0;
            exit when C_Rdtsc - T0 > 8_000_000_000;  -- ~4 s @ 2 GHz
         end loop;
      end;
      Schild_Nvme.Flush_Log_To_Nvme;

      -- Setup TX descriptor ring: mark all descriptors as done
      for I in 0 .. NUM_DESC - 1 loop
         Tx_Ring (I).Addr   := 0;
         Tx_Ring (I).Status := 1;  -- DD bit = done (owned by hardware)
      end loop;

      -- Setup RX descriptor ring: point each descriptor to its buffer
      -- (DMA descriptors use PHYSICAL addresses: C_Dma_Phys).
      for I in 0 .. NUM_DESC - 1 loop
         Rx_Ring (I).Addr   := C_Dma_Phys (Rx_Buf (I, 0)'Address);
         Rx_Ring (I).Status := 0;  -- owned by hardware (ready to receive)
      end loop;

      -- Point card to TX descriptor ring
      declare
         Ring_Addr : constant Unsigned_64 := C_Dma_Phys (Tx_Ring'Address);
         Msg_Ring : constant String := "[E1000E] Ring addr programmed";
      begin
         Mmio_Write (16#3800#, Unsigned_32 (Ring_Addr and 16#FFFFFFFF#));
         Mmio_Write (16#3804#, 0);
         Mmio_Write (16#3808#, Unsigned_32 (NUM_DESC * 16));
         Mmio_Write (16#3810#, 0);
         Mmio_Write (16#3818#, 0);
         C_Putln (Msg_Ring'Address, Msg_Ring'Length);
      end;

      -- Point card to RX descriptor ring
      declare
         Rx_Addr : constant Unsigned_64 := C_Dma_Phys (Rx_Ring'Address);
      begin
         Mmio_Write (16#2800#, Unsigned_32 (Rx_Addr and 16#FFFFFFFF#));
         Mmio_Write (16#2804#, 0);
         Mmio_Write (16#2808#, Unsigned_32 (NUM_DESC * 16));
         Mmio_Write (16#2810#, 0);
         Mmio_Write (16#2818#, Unsigned_32 (NUM_DESC - 1));
      end;

      -- NOTE: do NOT program RXDCTL/RDTR/RADV here.  Linux e1000e only applies
      -- E1000_RXDCTL_DMA_BURST_ENABLE (WTHRESH=4) under FLAG2_DMA_BURST, which
      -- is never set for the I219-V (PCH).  Setting WTHRESH=4 on this part
      -- makes the device batch descriptor write-backs, so a single inbound
      -- frame never sets the DD bit and RDH stays 0 (RX appears dead).  The
      -- reset default (WTHRESH=0) writes back each descriptor immediately.

      -- Enable TX (TCTL: EN | PSP | RTLC | CT=0x0F | COLD=0x40)
      Mmio_Write (16#0400#, 16#10400FA#);
      -- Enable RX (RCTL: EN | UPE | MPE | BAM | SBP=promisc | BSIZE=2048)
      Mmio_Write (16#0100#, 16#0000C00E#);
      -- Interrupt mask: TXDW | TXQE | LSC | RXT0 | RXDMT0 | RXO
      Mmio_Write (16#00D0#, 16#00000087# or 16#000000D0#);
      -- Interrupt Throttling (ITR): coalesce bursts at the source so a packet
      -- storm cannot starve the control plane. 0x7D0 = 2000 ticks @ 256ns =
      -- ~512us minimum inter-interrupt interval.
      Mmio_Write (16#00C4#, 16#000007D0#);

      -- Read and cache the device MAC from RAR0 (Receive Address Register 0):
      -- RAL0 @0x5400 holds bytes 0..3, RAH0 @0x5404 holds bytes 4..5 (low 16 bits).
      declare
         Mac_Low  : Unsigned_32 := Mmio_Read (16#5400#);
         Mac_High : Unsigned_32 := Mmio_Read (16#5404#);
      begin
         Cached_MAC (0) := Unsigned_8 (Mac_Low and 16#FF#);
         Cached_MAC (1) := Unsigned_8 (Interfaces.Shift_Right (Mac_Low, 8) and 16#FF#);
         Cached_MAC (2) := Unsigned_8 (Interfaces.Shift_Right (Mac_Low, 16) and 16#FF#);
         Cached_MAC (3) := Unsigned_8 (Interfaces.Shift_Right (Mac_Low, 24) and 16#FF#);
         Cached_MAC (4) := Unsigned_8 (Mac_High and 16#FF#);
         Cached_MAC (5) := Unsigned_8 (Interfaces.Shift_Right (Mac_High, 8) and 16#FF#);
      end;

      Ready := True;
      declare
         Msg_OK : constant String := "[E1000E] Init OK";
      begin
         C_Putln (Msg_OK'Address, Msg_OK'Length);
         Schild_Nvme.Flush_Log_To_Nvme;
      end;
   end Init_MMIO;

   -- Ring 0 (standalone kernel) path: PCI scan via port I/O, then identity-map
   -- the BAR0 2MB page (3-4GB range) and delegate to Init_MMIO.
   procedure Init is
      Info : Schild_Pci_Scanner.Pci_Device_Info;
      Msg_Scan : constant String := "[E1000E] Scanning PCI...";
      Msg_Found: constant String := "[E1000E] Device found, MMIO mapped";
   begin
      C_Putln (Msg_Scan'Address, Msg_Scan'Length);
      Schild_Nvme.Flush_Log_To_Nvme;
      --  NOTE (validation status): the register model has been validated only
      --  against QEMU's Intel 82540EM (e1000, device 100E) — the path that
      --  reaches "Init OK" and completes TX/RX. The 82574L (10D3, QEMU's
      --  e1000e model) and the target I219-V (15D8) paths are present but NOT
      --  yet validated: under `-device e1000e` init does not complete (stops
      --  after ring programming). I219-V validation needs real T580 hardware.
      Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#10D3#);
      if not Info.Found then
         -- Try Intel I219-V (T580)
         Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#15D8#);
      end if;
      if not Info.Found then
         -- Try Intel 82540EM (older e1000 in QEMU)
         Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#100E#);
      end if;
      if not Info.Found then
         -- Try Intel 82574L alt ID
         Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#10EA#);
      end if;
      if not Info.Found then
         declare
            Msg_NF : constant String := "[E1000E] Not found";
         begin
            C_Putln (Msg_NF'Address, Msg_NF'Length);
         end;
         return;
      end if;
      C_Putln (Msg_Found'Address, Msg_Found'Length);
      Schild_Nvme.Flush_Log_To_Nvme;

      -- Enable PCI bus-mastering so the NIC DMA engine can read descriptors and
      -- write back status (DD bit). Without this the MMIO registers respond but
      -- the TX/RX rings in host RAM are unreachable to the device.
      Schild_Pci_Scanner.Enable_Bus_Master (Info.Bus, Info.Device, Info.Func);

      -- Map MMIO region in page tables (needed for 3-4GB BAR0 range)
      C_Map_MMIO (Unsigned_64 (Info.BAR0 and 16#FFFFFFF0#) and not 16#1FFFFF#);

      -- Delegate reset + ring setup (MMIO base = physical BAR0, identity-mapped)
      Init_MMIO (Unsigned_64 (Info.BAR0 and 16#FFFFFFF0#));

      -- Register MMIO with C handler and configure IOAPIC (Ring 0 only)
      C_Set_MMIO (Unsigned_64 (Info.BAR0 and 16#FFFFFFF0#));
      declare
         Msg_Irq : constant String := "[E1000E] IRQ line = 0x";
      begin
         C_Putln (Msg_Irq'Address, Msg_Irq'Length);
         C_Log_Hex32 (Info.IRQ_Line);
      end;
      -- Prefer MSI (bypasses the IOAPIC; works when IRQ_Line is 0xFF).  Fall
      -- back to the legacy IOAPIC pin only if the device lacks MSI capability.
      if Schild_Pci_Scanner.Enable_MSI (Info.Bus, Info.Device, Info.Func, 16#30#) then
         declare
            Msg_Msi : constant String := "[E1000E] MSI enabled (vector 0x30)";
            Msg_Mc  : constant String := "[E1000E] MSI msg_ctrl=0x";
         begin
            C_Putln (Msg_Msi'Address, Msg_Msi'Length);
            C_Putln (Msg_Mc'Address, Msg_Mc'Length);
            C_Log_Hex32 (Schild_Pci_Scanner.Read_MSI_Control
                           (Info.Bus, Info.Device, Info.Func));
         end;
      else
         C_Ioapic_Unmask (Info.IRQ_Line, 16#30#);  -- Vector 0x30 (legacy INTx)
         declare
            Msg_Intx : constant String := "[E1000E] INTx fallback (IOAPIC)";
         begin
            C_Putln (Msg_Intx'Address, Msg_Intx'Length);
         end;
      end if;
   end Init;

   function Is_Ready return Boolean is (Ready);

   -- Acknowledge the device-level interrupt by reading ICR (read-to-clear).
   -- Called from the NetServer poll path before the seL4 IRQ handler is acked.
   procedure Clear_IRQ is
   begin
      if not Ready then
         return;
      end if;
      declare
         Cause : Unsigned_32 := Mmio_Read (16#00C0#);  -- ICR: read-to-clear
      begin
         if Cause = 0 then
            null;  -- no pending cause (spurious or already cleared)
         end if;
      end;
   end Clear_IRQ;

   function Read_ICR return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      return Mmio_Read (16#00C0#);  -- ICR: read-to-clear (diagnostic)
   end Read_ICR;

   function Read_RDH return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      return Mmio_Read (16#2810#);  -- RX Descriptor Head (diagnostic)
   end Read_RDH;

   function Rx_DD return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      -- DD (Descriptor Done) is bit 0 of the RX descriptor status byte (offset
      -- 12), which the device sets via DMA once a frame has been received.
      return Unsigned_32 (Rx_Ring (0).Status and 1);
   end Rx_DD;

   function Read_Status return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      return Mmio_Read (16#0008#);  -- STATUS: bit 1 = link up
   end Read_Status;

   function Read_RCTL return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      return Mmio_Read (16#0100#);  -- RCTL: bit 0 = RX enable
   end Read_RCTL;

   function Read_CTRL return Unsigned_32 is
   begin
      if not Ready then
         return 0;
      end if;
      return Mmio_Read (16#0000#);  -- CTRL: SLU/FRCSPD/FRCDPX/PHY_RST/RST
   end Read_CTRL;

   function Get_MAC return Mac_Addr is
   begin
      return Cached_MAC;
   end Get_MAC;

   -- Send raw ethernet frame via DMA descriptor ring.
   -- Uses a single shared buffer (Tx_Buf) — suitable for single-packet test.
   -- Production: replace with buffer pool to avoid in-flight DMA corruption.
   procedure Send_Packet (Data : Unsigned_8_Array; Len : Unsigned_16) is
      Idx      : constant Unsigned_32 := Tx_Idx mod Unsigned_32 (NUM_DESC);
      Buf_Addr : Unsigned_64;
      Timeout  : Integer := 0;
   begin
      if not Ready then return; end if;
      if Len > TX_BUF_SIZE then return; end if;

      -- Wait for descriptor availability with timeout (prevents infinite hang)
      -- DD bit (status bit 0): 0 = owned by hardware, 1 = done/free
      while (Tx_Ring (Integer (Idx)).Status and 1) = 0 loop
         Timeout := Timeout + 1;
         exit when Timeout > 100_000;  -- ~100ms at typical bus speed
      end loop;
      if Timeout > 100_000 then return; end if;

      -- Copy packet into this descriptor's dedicated TX buffer. A per-descriptor
      -- buffer pool avoids in-flight DMA corruption when multiple frames are
      -- queued back-to-back (previously all descriptors shared one Tx_Buf).
      for I in 0 .. Integer (Unsigned_16'Min (Len, Unsigned_16 (TX_BUF_SIZE))) - 1 loop
         Tx_Buf (Integer (Idx), Integer (I)) := Data (Data'First + I);
      end loop;

      -- Program descriptor: buffer address, length, commands
      -- Cmd bits: 1=EOP (end of packet), 2=IFCS (insert FCS), 8=RS (report status)
      Buf_Addr := C_Dma_Phys (Tx_Buf (Integer (Idx), 0)'Address);
      Tx_Ring (Integer (Idx)).Addr   := Buf_Addr;
      Tx_Ring (Integer (Idx)).Len    := Len;
      Tx_Ring (Integer (Idx)).Cmd    := 1 or 2 or 8;
      Tx_Ring (Integer (Idx)).Status := 0;  -- hand over to hardware

      -- Advance tail pointer (doorbell): notifies card of new descriptor
      Tx_Idx := Tx_Idx + 1;
      -- Flush the TX buffer and descriptor from cache BEFORE ringing the
      -- doorbell. CLFLUSH invalidates a SINGLE 64-byte cache line, so a frame
      -- longer than one line (e.g. the ~500-byte HTTP response) must have every
      -- line flushed; otherwise the DMA engine reads stale bytes past the first
      -- 64 and the peer drops the frame on a bad checksum.
      declare
         Line_Size : constant Integer := 64;
         Off       : Integer := 0;
      begin
         loop
            C_ClFlush (Tx_Buf (Integer (Idx), Off)'Address);
            exit when Off + Line_Size >= Integer (Len);
            Off := Off + Line_Size;
         end loop;
      end;
      C_ClFlush (Tx_Ring (Integer (Idx))'Address);
       
      Mmio_Write (16#3818#, Unsigned_32 ((Idx + 1) mod Unsigned_32 (NUM_DESC)));

      -- Wait for TX completion: DD bit set by hardware
      Timeout := 0;
      while (Tx_Ring (Integer (Idx)).Status and 1) = 0 loop
         Timeout := Timeout + 1;
         exit when Timeout > 100_000;
      end loop;
      if Timeout > 100_000 then
         C_Putln (Msg_TX_TO'Address, Msg_TX_TO'Length);
      end if;
   end Send_Packet;

   -- Poll for received packet (no interrupts needed).
   -- Checks RX descriptor at current head index.
   -- Returns True and copies data to Buf if a packet was received.
   function Poll_Rx (Buf : out Unsigned_8_Array; Len : out Interfaces.Unsigned_16) return Boolean is
      Idx : constant Unsigned_32 := Rx_Idx mod Unsigned_32 (NUM_DESC);
   begin
      Len := 0;
      if not Ready then return False; end if;
      -- DD bit (status bit 0) = 1 means hardware has written a packet
      if (Rx_Ring (Integer (Idx)).Status and 1) = 0 then
         return False;
      end if;
      -- Copy received data to output buffer
      declare
         Pkt_Len : constant Unsigned_16 := Rx_Ring (Integer (Idx)).Len;
         Copy_Len : constant Integer := Integer (Unsigned_16'Min (Pkt_Len, Unsigned_16 (Buf'Length)));
      begin
         Len := Pkt_Len;
         for I in 0 .. Copy_Len - 1 loop
            Buf (Buf'First + I) := Rx_Buf (Integer (Idx), I);
         end loop;
      end;
      -- Hand descriptor back to hardware
      Rx_Ring (Integer (Idx)).Status := 0;
      Rx_Idx := Rx_Idx + 1;
      -- Update tail pointer: RDT is the boundary the hardware writes up to
      -- (exclusive). Set it to the descriptor just freed so the ring keeps
      -- accepting packets; Idx+1 would make RDH==RDT after the first frame and
      -- the device would drop every subsequent packet.
      Mmio_Write (16#2818#, Idx);
      return True;
   end Poll_Rx;

end Schild_E1000e;
