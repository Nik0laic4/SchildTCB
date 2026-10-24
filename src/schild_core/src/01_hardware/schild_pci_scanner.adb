-- Schild TCB PCI Scanner — enumeration of PCI/PCIe bus via Configuration Space.
-- Supports both legacy Port I/O (0xCF8/0xCFC) and ECAM (MMIO config access).
-- Legacy 0xCF8 only reaches bus 0 (and a few bridges) on modern chipsets; the
-- M.2 NVMe behind a PCIe root port (bus 40 on the T580) is only reachable via
-- ECAM. The ECAM base is read from PCIEXBAR (00:00.0 offset 0x60).
with System.Machine_Code; with Interfaces; with Schild_Uart_Driver;
package body Schild_Pci_Scanner with SPARK_Mode => Off is
   use Interfaces;

   procedure C_Map_MMIO (Phys_Addr : Unsigned_64);
   pragma Import (C, C_Map_MMIO, "schild_map_mmio_2mb");

   -- ECAM state (MMIO configuration access). The ECAM window is mapped into
   -- pd_table2 (3-4 GB range) on demand via schild_map_mmio_2mb.
   Ecam_Base   : Unsigned_64 := 0;
   Ecam_Inited : Boolean := False;
   Ecam_Mapped : Unsigned_64 := 0;   -- 2MB page currently mapped

   -- Legacy config read via port I/O (0xCF8/0xCFC). Only bus 0 is guaranteed
   -- reachable on modern chipsets; buses behind PCIe root ports need ECAM.
   function Legacy_Read (Bus, Dev, Func, Off : Unsigned_32) return Unsigned_32 is
      -- PCI Configuration Address: [31]=Enable, [23:16]=Bus, [15:11]=Dev,
      -- [10:8]=Func, [7:2]=Register, [1:0]=00
      A : Unsigned_32 := Bus*2**16 + Dev*2**11 + Func*2**8 + (Off and 16#FC#) + 16#80000000#;
      R : Unsigned_32;
   begin
      System.Machine_Code.Asm (
        "outl %0, %1; nop; nop",
        Outputs => System.Machine_Code.No_Output_Operands,
        Inputs  => (Unsigned_32'Asm_Input ("a", A),
                     Unsigned_32'Asm_Input ("Nd", 16#CF8#)),
        Volatile => True);
      System.Machine_Code.Asm (
        "inl %1, %0",
        Outputs => Unsigned_32'Asm_Output ("=a", R),
        Inputs  => Unsigned_32'Asm_Input ("Nd", 16#CFC#),
        Volatile => True);
      return R;
   end Legacy_Read;

   procedure Legacy_Write (Bus, Dev, Func, Off, Val : Unsigned_32) is
      A : Unsigned_32 := Bus*2**16 + Dev*2**11 + Func*2**8 + (Off and 16#FC#) + 16#80000000#;
   begin
      System.Machine_Code.Asm (
        "outl %0, %1; nop; nop",
        Outputs => System.Machine_Code.No_Output_Operands,
        Inputs  => (Unsigned_32'Asm_Input ("a", A),
                    Unsigned_32'Asm_Input ("Nd", 16#CF8#)),
        Volatile => True);
      System.Machine_Code.Asm (
        "outl %0, %1",
        Outputs => System.Machine_Code.No_Output_Operands,
        Inputs  => (Unsigned_32'Asm_Input ("a", Val),
                    Unsigned_32'Asm_Input ("Nd", 16#CFC#)),
        Volatile => True);
   end Legacy_Write;

   -- Read the ECAM base from PCIEXBAR (00:00.0 offset 0x60). The register is
   -- 64-bit: bits 0 = enable, bits 3..31 = base (256MB-aligned). On the T580
   -- it reads 0xF0000003 → base 0xF0000000, 128MB window (buses 0..127).
   procedure Init_Ecam is
      Pxbar : Unsigned_32;
   begin
      Ecam_Inited := True;
      Pxbar := Legacy_Read (0, 0, 0, 16#60#);
      if (Pxbar and 1) /= 0 then
         declare
            Base : constant Unsigned_64 := Unsigned_64 (Pxbar and 16#FFFFFFF8#);
         begin
            -- Only enable ECAM when its window lies in the 3-4 GB range that
            -- pd_table2 (schild_map_mmio_2mb) can identity-map. The T580's
            -- ECAM is at 0xF0000000 (buses 0..127).
            if Base >= 16#C0000000# and then Base < 16#1_0000_0000# then
               Ecam_Base := Base;
               Schild_Uart_Driver.Put_Line ("[PCI] ECAM config access enabled");
            else
               Schild_Uart_Driver.Put_Line ("[PCI] ECAM below 3GB - legacy fallback");
            end if;
         end;
      else
         Schild_Uart_Driver.Put_Line ("[PCI] ECAM disabled - legacy fallback");
      end if;
   end Init_Ecam;

   function Ecam_Read (Bus, Dev, Func, Off : Unsigned_32) return Unsigned_32 is
      Addr : Unsigned_64;
      Page : Unsigned_64;
      V    : Unsigned_32;
   begin
      Addr := Ecam_Base
        + Shift_Left (Unsigned_64 (Bus), 20)
        + Shift_Left (Unsigned_64 (Dev), 15)
        + Shift_Left (Unsigned_64 (Func), 12)
        + Unsigned_64 (Off and 16#FFC#);
      Page := Addr and not 16#1FFFFF#;
      if Page /= Ecam_Mapped then
         C_Map_MMIO (Page);
         Ecam_Mapped := Page;
      end if;
      System.Machine_Code.Asm ("movl (%1), %0",
        Outputs => Unsigned_32'Asm_Output ("=r", V),
        Inputs  => Unsigned_64'Asm_Input ("r", Addr),
        Volatile => True);
      return V;
   end Ecam_Read;

   procedure Ecam_Write (Bus, Dev, Func, Off, Val : Unsigned_32) is
      Addr : Unsigned_64;
      Page : Unsigned_64;
   begin
      Addr := Ecam_Base
        + Shift_Left (Unsigned_64 (Bus), 20)
        + Shift_Left (Unsigned_64 (Dev), 15)
        + Shift_Left (Unsigned_64 (Func), 12)
        + Unsigned_64 (Off and 16#FFC#);
      Page := Addr and not 16#1FFFFF#;
      if Page /= Ecam_Mapped then
         C_Map_MMIO (Page);
         Ecam_Mapped := Page;
      end if;
      System.Machine_Code.Asm ("movl %0, (%1)",
        Outputs => System.Machine_Code.No_Output_Operands,
        Inputs  => (Unsigned_32'Asm_Input ("r", Val),
                    Unsigned_64'Asm_Input ("r", Addr)),
        Volatile => True);
   end Ecam_Write;

   -- ECAM-aware read: prefer ECAM for buses 0..127, else legacy 0xCF8.
   function Pci_Read (Bus, Dev, Func, Off : Unsigned_32) return Unsigned_32 is
   begin
      if not Ecam_Inited then
         Init_Ecam;
      end if;
      if Ecam_Base /= 0 and then Ecam_Base < 16#1_0000_0000# and then Bus < 128 then
         return Ecam_Read (Bus, Dev, Func, Off);
      end if;
      return Legacy_Read (Bus, Dev, Func, Off);
   end Pci_Read;

   procedure Pci_Write (Bus, Dev, Func, Off, Val : Unsigned_32) is
   begin
      if not Ecam_Inited then
         Init_Ecam;
      end if;
      if Ecam_Base /= 0 and then Ecam_Base < 16#1_0000_0000# and then Bus < 128 then
         Ecam_Write (Bus, Dev, Func, Off, Val);
         return;
      end if;
      Legacy_Write (Bus, Dev, Func, Off, Val);
   end Pci_Write;

   procedure Enable_Bus_Master (Bus, Dev, Func : Unsigned_32) is
      Cmd : Unsigned_32 := Pci_Read (Bus, Dev, Func, 16#04#);
   begin
      --  COMMAND: bit 0 = I/O space, bit 1 = memory space, bit 2 = bus master.
      Cmd := Cmd or 16#00000007#;
      Pci_Write (Bus, Dev, Func, 16#04#, Cmd);
   end Enable_Bus_Master;

   function Enable_MSI (Bus, Dev, Func, Vector : Unsigned_32) return Boolean is
      Cap_Off : Unsigned_32;
      Hdr     : Unsigned_32;
      Msg_Ctl : Unsigned_32;
   begin
      -- PCI Capabilities Pointer (offset 0x34), low 8 bits.
      Cap_Off := Pci_Read (Bus, Dev, Func, 16#34#) and 16#FF#;

      for I in 1 .. 16 loop
         exit when Cap_Off = 0 or Cap_Off > 16#FC#;
         Hdr := Pci_Read (Bus, Dev, Func, Cap_Off);
         if (Hdr and 16#FF#) = 16#05# then  -- MSI capability
            -- Message Control is bits 16..31 of the DWORD at Cap_Off.  Pci_Read/
            -- Pci_Write mask the offset to a DWORD boundary, so "Cap_Off + 2"
            -- would alias Cap_Off and never touch the Message Control register.
            Msg_Ctl := Shift_Right (Hdr, 16) and 16#FFFF#;
            if (Msg_Ctl and 16#0080#) /= 0 then  -- 64-bit address capable
               Pci_Write (Bus, Dev, Func, Cap_Off + 4, 16#FEE00000#);
               Pci_Write (Bus, Dev, Func, Cap_Off + 8, 0);
               Pci_Write (Bus, Dev, Func, Cap_Off + 12, Vector and 16#FFFF#);
            else
               Pci_Write (Bus, Dev, Func, Cap_Off + 4, 16#FEE00000#);
               Pci_Write (Bus, Dev, Func, Cap_Off + 8, Vector and 16#FFFF#);
            end if;
            -- Enable MSI: set Message Control bit 0 (bit 16 of the Cap_Off
            -- DWORD).  Hdr still holds CapID/Next in bits 0..15; the address/
            -- data writes above only touched Cap_Off+4..+15, so Hdr is valid.
            Pci_Write (Bus, Dev, Func, Cap_Off, Hdr or 16#0001_0000#);
            return True;
         end if;
         Cap_Off := Shift_Right (Hdr, 8) and 16#FF#;  -- next capability pointer
      end loop;
      return False;
   end Enable_MSI;

   function Read_MSI_Control (Bus, Dev, Func : Unsigned_32) return Unsigned_32 is
      Cap_Off : Unsigned_32 := Pci_Read (Bus, Dev, Func, 16#34#) and 16#FF#;
      Hdr     : Unsigned_32;
   begin
      for I in 1 .. 16 loop
         exit when Cap_Off = 0 or Cap_Off > 16#FC#;
         Hdr := Pci_Read (Bus, Dev, Func, Cap_Off);
         if (Hdr and 16#FF#) = 16#05# then  -- MSI capability
            return Shift_Right (Hdr, 16) and 16#FFFF#;  -- Message Control
         end if;
         Cap_Off := Shift_Right (Hdr, 8) and 16#FF#;
      end loop;
      return 0;
   end Read_MSI_Control;

   function Find_Device (Vendor_Id, Device_Id : Unsigned_32) return Pci_Device_Info is
      Info : Pci_Device_Info; D : Unsigned_32;
   begin
      Info.Found := False;
      -- Scan all 256 buses and all 8 functions per device. The T580 puts the
      -- M.2 NVMe (SM981) on bus 40 and the I219-V Ethernet on function 6 of the
      -- 00:1f PCH, both outside the previous 0..2 bus / function-0 scan.
      for Bus in Unsigned_32 range 0 .. 255 loop
         for Slot in Unsigned_32 range 0 .. 31 loop
            for Func in Unsigned_32 range 0 .. 7 loop
               D := Pci_Read (Bus, Slot, Func, 0);
               -- Vendor 0xFFFF = no device present at this slot/function.
               if (D and 16#FFFF#) = 16#FFFF# then
                  -- Abort the whole slot only when function 0 is empty;
                  -- multi-function devices may have gaps between functions.
                  exit when Func = 0;
               elsif (D and 16#FFFF#) = Vendor_Id and then
                  (Shift_Right (D, 16) and 16#FFFF#) = Device_Id then
                  Info.Found := True;
                  Info.Bus := Bus; Info.Device := Slot; Info.Func := Func;
                  Info.Vendor_Id := (D and 16#FFFF#);
                  Info.Device_Id := Shift_Right (D, 16) and 16#FFFF#;
                  -- BAR0 at offset 0x10 — first memory-mapped I/O region.
                  -- Low 4 bits cleared: BAR0[3:0] encode type (memory=0, IO=1).
                  Info.BAR0 := Pci_Read (Bus, Slot, Func, 16#10#);
                  -- Interrupt Line at offset 0x3C — ISA IRQ number (for IOAPIC routing)
                  Info.IRQ_Line := Pci_Read (Bus, Slot, Func, 16#3C#) and 16#FF#;
                  Schild_Uart_Driver.Put_Line ("[PCI] Device found");
                  return Info;
               end if;
            end loop;
         end loop;
      end loop;
      return Info;
   end;
end Schild_Pci_Scanner;
