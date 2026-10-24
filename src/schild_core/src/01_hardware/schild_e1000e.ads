with Interfaces;
package Schild_E1000e with SPARK_Mode => Off is
   type Unsigned_8_Array is array (Integer range <>) of Interfaces.Unsigned_8;
   type Mac_Addr is array (0 .. 5) of Interfaces.Unsigned_8;
   procedure Init;
   -- Initialize using a pre-mapped MMIO window (Ring 3 / NetServer path).
   -- MMIO_VAddr is the virtual address the Root Task mapped the device BAR0 to
   -- (e.g. 0x600000 via X86PageMap). No PCI scan, no page-table edit, no IOAPIC.
   procedure Init_MMIO (MMIO_VAddr : Interfaces.Unsigned_64);
   function Is_Ready return Boolean;
   -- Return the device MAC read from RAR0 during Init_MMIO (real NIC address).
   function Get_MAC return Mac_Addr;
   procedure Send_Packet (Data : Unsigned_8_Array; Len : Interfaces.Unsigned_16);
   -- Poll for received packet. Returns True if packet was received.
   function Poll_Rx (Buf : out Unsigned_8_Array; Len : out Interfaces.Unsigned_16) return Boolean;
   -- Read a device register (MMIO). In QEMU this yields the vCPU to the event
   -- loop so queued network frames can be delivered to the model.
   procedure Poll_Status;
   -- Acknowledge/clear the device-level interrupt: read ICR (Interrupt Cause
   -- Read) at offset 0xC0, which is read-to-clear and de-asserts INTx. Must be
   -- called before the seL4 IRQ handler is acked, otherwise the device keeps
   -- asserting INTx and the IRQ re-fires immediately.
   procedure Clear_IRQ;
   -- Read the Interrupt Cause Register (0xC0, read-to-clear).  Diagnostic.
   function Read_ICR return Interfaces.Unsigned_32;
   -- Read the RX Descriptor Head register (0x2810): how many descriptors the
   -- device has DMA-written.  Diagnostic (0 => no frames arrived).
   function Read_RDH return Interfaces.Unsigned_32;
   -- DD bit of RX descriptor 0 (1 => the device received a frame).  Diagnostic.
   function Rx_DD return Interfaces.Unsigned_32;
   -- STATUS register (0x0008).  Diagnostic: bit 1 = link up (LU).
   function Read_Status return Interfaces.Unsigned_32;
   -- RCTL register (0x0100).  Diagnostic: bit 0 = RX enable (EN).
   function Read_RCTL return Interfaces.Unsigned_32;
   -- CTRL register (0x0000).  Diagnostic: SLU=0x40, FRCSPD=0x800, FRCDPX=0x1000,
   -- RST=0x04000000, PHY_RST=0x80000000.
   function Read_CTRL return Interfaces.Unsigned_32;
end Schild_E1000e;
