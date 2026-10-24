--  PCI bus scanner (enumerate devices by vendor/device id).
with Interfaces;
package Schild_Pci_Scanner with SPARK_Mode => Off is
   type Pci_Device_Info is record
      Found      : Boolean := False;
      Bus        : Interfaces.Unsigned_32 := 0;
      Device     : Interfaces.Unsigned_32 := 0;
      Func       : Interfaces.Unsigned_32 := 0;
      Vendor_Id  : Interfaces.Unsigned_32 := 0;
      Device_Id  : Interfaces.Unsigned_32 := 0;
      BAR0       : Interfaces.Unsigned_32 := 0;
      IRQ_Line   : Interfaces.Unsigned_32 := 0;  -- PCI Interrupt Line (0x3C)
   end record;
   function Find_Device (Vendor_Id, Device_Id : Interfaces.Unsigned_32) return Pci_Device_Info;
   -- Enable PCI bus-mastering (COMMAND register bit 2) so the device can DMA
   -- (read descriptors, write status). Without it MMIO registers still respond
   -- but the DMA engine cannot access host memory.
   procedure Enable_Bus_Master (Bus, Dev, Func : Interfaces.Unsigned_32);
   -- Enable MSI (Message Signaled Interrupts): the device writes interrupts
   -- directly to the LAPIC (at Vector) via a memory write, bypassing the IOAPIC.
   -- Needed when the PCI Interrupt Line (0x3C) is 0xFF (BIOS did not assign a
   -- legacy INTx IRQ).  Returns True if the MSI capability was found + enabled.
   function Enable_MSI (Bus, Dev, Func, Vector : Interfaces.Unsigned_32)
                        return Boolean;
   -- Read back the MSI Message Control register (16 bits) for diagnostics:
   -- bit 0 = MSI Enable, bit 7 = 64-bit capable.  0 if no MSI capability.
   function Read_MSI_Control (Bus, Dev, Func : Interfaces.Unsigned_32)
                              return Interfaces.Unsigned_32;
end Schild_Pci_Scanner;
