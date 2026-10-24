-- Schild TCB e1000e Driver (Intel 82574L / I219-V)
--  MMIO register layout, legacy TX/RX descriptor rings and the init sequence
--  (PCI scan, MAC/PHY reset, ring setup, interrupt enable).

with System.Machine_Code;
with System.Storage_Elements;
use type System.Storage_Elements.Integer_Address;
with Interfaces;
with Schild_Uart_Driver;
with Schild_Pci_Scanner;


package body Schild_E1000e_Driver with
  SPARK_Mode => Off
is
   use Interfaces;

   function C_Get_Addr (A : System.Address) return Unsigned_64;
   pragma Import (C, C_Get_Addr, "schild_ptr_to_u64");
   function C_Get_Addr32 (A : System.Address) return Unsigned_32;
   pragma Import (C, C_Get_Addr32, "schild_ptr_to_u32_low");


   -- ============================================================
   --  MMIO register offsets.
   -- ============================================================
   REG_CTRL     : constant := 16#0000#;  -- Device Control
   REG_STATUS   : constant := 16#0008#;  -- Device Status
   REG_EERD     : constant := 16#0014#;  -- EEPROM Read
   REG_CTRL_EXT : constant := 16#0018#;  -- Extended Control
   REG_MDIC     : constant := 16#0020#;  -- MDI Control
   REG_FCAL     : constant := 16#0028#;  -- Flow Control Address Low
   REG_FCAH     : constant := 16#002C#;  -- Flow Control Address High
   REG_ICR      : constant := 16#00C0#;  -- Interrupt Cause Read
   REG_ICS      : constant := 16#00C8#;  -- Interrupt Cause Set
   REG_IMS      : constant := 16#00D0#;  -- Interrupt Mask Set/Read
   REG_IMC      : constant := 16#00D8#;  -- Interrupt Mask Clear
   REG_RCTL     : constant := 16#0100#;  -- Receive Control
   REG_TCTL     : constant := 16#0400#;  -- Transmit Control
   REG_TDBAL    : constant := 16#3800#;  -- TX Descriptor Base Low
   REG_TDBAH    : constant := 16#3804#;  -- TX Descriptor Base High
   REG_TDLEN    : constant := 16#3808#;  -- TX Descriptor Length
   REG_TDH      : constant := 16#3810#;  -- TX Descriptor Head
   REG_TDT      : constant := 16#3818#;  -- TX Descriptor Tail
   REG_RDBAL    : constant := 16#2800#;  -- RX Descriptor Base Low
   REG_RDBAH    : constant := 16#2804#;  -- RX Descriptor Base High
   REG_RDLEN    : constant := 16#2808#;  -- RX Descriptor Length
   REG_RDH      : constant := 16#2810#;  -- RX Descriptor Head
   REG_RDT      : constant := 16#2818#;  -- RX Descriptor Tail
   REG_RAL0     : constant := 16#5400#;  -- Receive Address Low
   REG_RAH0     : constant := 16#5404#;  -- Receive Address High
   REG_MTA      : constant := 16#5200#;  -- Multicast Table Array

   -- Control bits
   CTRL_ASDE    : constant := 16#00000020#;
   CTRL_SLU     : constant := 16#00000040#;
   CTRL_FRCSPD  : constant := 16#00000800#;
   CTRL_FRCDPLX : constant := 16#00001000#;
   CTRL_RST     : constant := 16#04000000#;
   CTRL_PHY_RST : constant := 16#80000000#;

   -- TX Control
   TCTL_EN      : constant := 16#00000002#;
   TCTL_PSP     : constant := 16#00000008#;
   TCTL_CT      : constant := 16#00000100#;

   -- RX Control
   RCTL_EN      : constant := 16#00000002#;
   RCTL_UPE     : constant := 16#00000008#;
   RCTL_MPE     : constant := 16#00000010#;
   RCTL_BAM     : constant := 16#00008000#;
   RCTL_BSIZE   : constant := 16#00030000#;  -- Buffer size 2048

   -- Interrupt bits
   ICR_TXDW     : constant := 16#00000001#;  -- TX Descriptor Written Back
   ICR_TXQE     : constant := 16#00000002#;  -- TX Queue Empty
   ICR_LSC      : constant := 16#00000004#;  -- Link Status Change
   ICR_RXSEQ    : constant := 16#00000008#;  -- RX Sequence Error
   ICR_RXDMT0   : constant := 16#00000010#;  -- RX Descriptor Minimum Threshold
   ICR_RXO      : constant := 16#00000040#;  -- RX Overrun
   ICR_RXT0     : constant := 16#00000080#;  -- RX Timer

   -- ============================================================
   --  TX/RX Descriptors (Legacy mode)
   -- ============================================================
   type Tx_Descriptor is record
      Buffer_Addr : Unsigned_64;
      Length      : Unsigned_16;
      Cso         : Unsigned_8;
      Cmd         : Unsigned_8;
      Status      : Unsigned_8;
      Css         : Unsigned_8;
      Special     : Unsigned_16;
   end record;

   TX_CMD_EOP  : constant := 16#01#;  -- End Of Packet
   TX_CMD_IFCS : constant := 16#02#;  -- Insert FCS
   TX_CMD_RS   : constant := 16#08#;  -- Report Status

   type Rx_Descriptor is record
      Buffer_Addr : Unsigned_64;
      Length      : Unsigned_16;
      Checksum    : Unsigned_16;
      Status      : Unsigned_8;
      Errors      : Unsigned_8;
      Special     : Unsigned_16;
   end record;

   NUM_DESCRIPTORS : constant := 8;

   -- ============================================================
   --  Driver state: MMIO base, rings and buffers.
   -- ============================================================
   MMIO_Base   : Unsigned_64 := 0;
   Initialized : Boolean := False;
   Tx_Desc_Ring : array (0 .. NUM_DESCRIPTORS - 1) of Tx_Descriptor;
   Rx_Desc_Ring : array (0 .. NUM_DESCRIPTORS - 1) of Rx_Descriptor;
   Tx_Buffers   : array (0 .. NUM_DESCRIPTORS - 1, 0 .. 2047) of Unsigned_8;
   Rx_Buffers   : array (0 .. NUM_DESCRIPTORS - 1, 0 .. 2047) of Unsigned_8;
   Tx_Head      : Unsigned_32 := 0;
   Tx_Tail      : Unsigned_32 := 0;

   --  Read a 32-bit MMIO register at the given offset.
   function Mmio_Read32 (Offset : Unsigned_32) return Unsigned_32 is
      Addr : constant Unsigned_64 := MMIO_Base + Unsigned_64 (Offset);
      Val  : Unsigned_32;
   begin
      System.Machine_Code.Asm
        (Template => "movl (%1), %0",
         Outputs  => Unsigned_32'Asm_Output ("=r", Val),
         Inputs   => Unsigned_64'Asm_Input ("r", Addr),
         Volatile => True);
      return Val;
   end Mmio_Read32;

   --  Write a 32-bit MMIO register at the given offset.
   procedure Mmio_Write32 (Offset, Value : Unsigned_32) is
      Addr : constant Unsigned_64 := MMIO_Base + Unsigned_64 (Offset);
   begin
      System.Machine_Code.Asm
        (Template => "movl %0, (%1)",
         Inputs   => (Unsigned_32'Asm_Input ("r", Value),
                       Unsigned_64'Asm_Input ("r", Addr)),
         Volatile => True);
   end Mmio_Write32;

   --  Locate the NIC, reset it, set up TX/RX rings and enable interrupts.
   procedure Init is
      Info : Schild_Pci_Scanner.Pci_Device_Info;
      Ctrl : Unsigned_32;
   begin
      Schild_Uart_Driver.Put_Line ("[E1000E] Scanning PCI for Intel 82574L...");

      --  First look for the Intel 82574L (vendor 0x8086, device 0x10D3).
      Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#10D3#);

      if not Info.Found then
         --  Fall back to the I219-V (device 0x15D8).
         Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#15D8#);
      end if;

      if not Info.Found then
         Schild_Uart_Driver.Put_Line ("[E1000E] Device not found");
         return;
      end if;

      --  The MMIO base is BAR0, 16-byte aligned.
      MMIO_Base := Unsigned_64 (Info.BAR0 and 16#FFFFFFF0#);
      Schild_Uart_Driver.Put_Line ("[E1000E] Device found, MMIO mapped");

      -- Reset device
      Ctrl := Mmio_Read32 (Unsigned_32 (REG_CTRL));
      Mmio_Write32 (Unsigned_32 (REG_CTRL), Ctrl or CTRL_RST);
      for I in 1 .. 100000 loop null; end loop;  -- wait for reset

      -- Enable link
      Ctrl := Mmio_Read32 (Unsigned_32 (REG_CTRL));
      Mmio_Write32 (Unsigned_32 (REG_CTRL), Ctrl or CTRL_SLU);

      -- Setup TX descriptor ring
      for I in 0 .. NUM_DESCRIPTORS - 1 loop
         Tx_Desc_Ring (I).Buffer_Addr :=
           Unsigned_64 (System.Storage_Elements.To_Integer (Tx_Buffers (I, 0)'Address));
         Tx_Desc_Ring (I).Cmd := 0;
         Tx_Desc_Ring (I).Status := 1;  -- descriptor done
      end loop;

      -- Setup RX descriptor ring
      for I in 0 .. NUM_DESCRIPTORS - 1 loop
         Rx_Desc_Ring (I).Buffer_Addr :=
           Unsigned_64 (System.Storage_Elements.To_Integer (Rx_Buffers (I, 0)'Address));
      end loop;

      --  Point the TX ring registers at the descriptor rings.
      Mmio_Write32 (Unsigned_32 (REG_TDBAL),
        Unsigned_32 (System.Storage_Elements.To_Integer (Tx_Desc_Ring'Address) and 16#FFFFFFFF#));
      Mmio_Write32 (Unsigned_32 (REG_TDBAH), 0);
      Mmio_Write32 (Unsigned_32 (REG_TDLEN),
        Unsigned_32 (NUM_DESCRIPTORS * 16));  -- 16 bytes per descriptor

      Mmio_Write32 (Unsigned_32 (REG_RDBAL),
        Unsigned_32 (System.Storage_Elements.To_Integer (Rx_Desc_Ring'Address) and 16#FFFFFFFF#));
      Mmio_Write32 (Unsigned_32 (REG_RDBAH), 0);
      Mmio_Write32 (Unsigned_32 (REG_RDLEN),
        Unsigned_32 (NUM_DESCRIPTORS * 16));

      --  Reset the TX/RX head/tail pointers.
      Mmio_Write32 (Unsigned_32 (REG_TDH), 0);
      Mmio_Write32 (Unsigned_32 (REG_TDT), 0);
      Mmio_Write32 (Unsigned_32 (REG_RDH), 0);
      Mmio_Write32 (Unsigned_32 (REG_RDT), Unsigned_32 (NUM_DESCRIPTORS - 1));

      -- Enable TX
      Mmio_Write32 (Unsigned_32 (REG_TCTL), TCTL_EN or TCTL_PSP or (15 * TCTL_CT));

      -- Enable RX
      Mmio_Write32 (Unsigned_32 (REG_RCTL),
        RCTL_EN or RCTL_UPE or RCTL_MPE or RCTL_BAM or RCTL_BSIZE);

      -- Enable interrupts
      Mmio_Write32 (Unsigned_32 (REG_IMS), ICR_TXDW or ICR_TXQE or ICR_LSC);

      Initialized := True;
      Schild_Uart_Driver.Put_Line ("[E1000E] Initialized: TX+RX rings, interrupts enabled");
   end Init;

   function Is_Ready return Boolean is (Initialized);

end Schild_E1000e_Driver;
