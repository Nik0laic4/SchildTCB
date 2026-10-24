-- Schild TCB NVMe Driver — Admin Queue + I/O Queues + Read/Write.
-- Supports Samsung SM981 (T580) and QEMU NVMe (-device nvme,serial=...).

with System; with System.Machine_Code; with Interfaces;

with Schild_Uart_Driver; with Schild_Pci_Scanner;

package body Schild_Nvme with SPARK_Mode => Off is
   use Interfaces;

   function C_Addr  (A : System.Address) return Unsigned_64;
   pragma Import (C, C_Addr, "schild_dma_phys");
   procedure C_Map_MMIO (Phys_Addr : Unsigned_64);
   pragma Import (C, C_Map_MMIO, "schild_map_mmio_2mb");
   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");
   procedure C_Set_Ext_ACQ (Addr : Unsigned_64);
   pragma Import (C, C_Set_Ext_ACQ, "schild_nvme_set_ext_acq");
   function C_Poll_ACQ return Unsigned_32;
   pragma Import (C, C_Poll_ACQ, "schild_nvme_poll_acq");

   MMIO  : Unsigned_64 := 0;
   Ready : Boolean := False;

   -- 4KB Identify data buffer (aligned to page)
   type Identify_Data is array (0 .. 4095) of Unsigned_8;
   Id_Buf : Identify_Data := (others => 0)
     with Alignment => 4096;
   Id_Info : Identify_Info;

   -- Admin queues (2 entries each = ASQS=1, ACQS=1; 4KB-aligned)
   type SQ_Entry is array (0 .. 63) of Unsigned_8;
   type Admin_SQ_Array is array (0 .. 127) of Unsigned_8;  -- 2 × 64 bytes
   ASQ : Admin_SQ_Array := (others => 0)
     with Alignment => 4096;
   type CQ_Entry is array (0 .. 15) of Unsigned_8;
   type Admin_CQ_Array is array (0 .. 31) of Unsigned_8;   -- 2 × 16 bytes
   ACQ : Admin_CQ_Array := (others => 0)
     with Alignment => 4096;

   -- I/O queues (2 entries each = QSIZE=1, 4KB-aligned)
   type IO_SQ_Array is array (0 .. 127) of Unsigned_8;  -- 2 × 64 bytes
   type IO_CQ_Array is array (0 .. 31) of Unsigned_8;   -- 2 × 16 bytes
   IOSQ : IO_SQ_Array := (others => 0)
     with Alignment => 4096;
   IOCQ : IO_CQ_Array := (others => 0)
     with Alignment => 4096;

   -- Read/Write data buffer (512 bytes, page-aligned for NVMe PRP)
   RW_Buf : Block_Buf := (others => 0)
     with Alignment => 4096;

   -- NVMe doorbell stride + external ACQ flag
   DB_Stride    : Unsigned_32 := 4;
   Use_Ext_ACQ  : Boolean := False;

   procedure Mmio_Write (Off : Unsigned_32; Val : Unsigned_32) is
      A : constant Unsigned_64 := MMIO + Unsigned_64 (Off);
   begin
      System.Machine_Code.Asm ("movl %0, (%1)",
        Inputs => (Unsigned_32'Asm_Input ("r", Val),
                    Unsigned_64'Asm_Input ("r", A)),
        Volatile => True);
   end;

   function Mmio_Read (Off : Unsigned_32) return Unsigned_32 is
      A : constant Unsigned_64 := MMIO + Unsigned_64 (Off);
      V : Unsigned_32;
   begin
      System.Machine_Code.Asm ("movl (%1), %0",
        Outputs => Unsigned_32'Asm_Output ("=r", V),
        Inputs  => Unsigned_64'Asm_Input ("r", A), Volatile => True);
      return V;
   end;

   -- Write a 64-bit physical address into SQ_Entry at byte offset Off
   procedure Set_PRPS (SQ : in out Admin_SQ_Array; Off : Unsigned_32; Addr : Unsigned_64) is
      use type Unsigned_64;
   begin
      SQ (Integer (Off) + 0) := Unsigned_8 ( Addr         and 16#FF#);
      SQ (Integer (Off) + 1) := Unsigned_8 ((Addr / 2**8)  and 16#FF#);
      SQ (Integer (Off) + 2) := Unsigned_8 ((Addr / 2**16) and 16#FF#);
      SQ (Integer (Off) + 3) := Unsigned_8 ((Addr / 2**24) and 16#FF#);
      SQ (Integer (Off) + 4) := Unsigned_8 ((Addr / 2**32) and 16#FF#);
      SQ (Integer (Off) + 5) := Unsigned_8 ((Addr / 2**40) and 16#FF#);
      SQ (Integer (Off) + 6) := Unsigned_8 ((Addr / 2**48) and 16#FF#);
      SQ (Integer (Off) + 7) := Unsigned_8 ((Addr / 2**56) and 16#FF#);
   end Set_PRPS;

   procedure Set_PRPS_Io (SQ : in out IO_SQ_Array; Off : Unsigned_32; Addr : Unsigned_64) is
      use type Unsigned_64;
   begin
      SQ (Integer (Off) + 0) := Unsigned_8 ( Addr         and 16#FF#);
      SQ (Integer (Off) + 1) := Unsigned_8 ((Addr / 2**8)  and 16#FF#);
      SQ (Integer (Off) + 2) := Unsigned_8 ((Addr / 2**16) and 16#FF#);
      SQ (Integer (Off) + 3) := Unsigned_8 ((Addr / 2**24) and 16#FF#);
      SQ (Integer (Off) + 4) := Unsigned_8 ((Addr / 2**32) and 16#FF#);
      SQ (Integer (Off) + 5) := Unsigned_8 ((Addr / 2**40) and 16#FF#);
      SQ (Integer (Off) + 6) := Unsigned_8 ((Addr / 2**48) and 16#FF#);
      SQ (Integer (Off) + 7) := Unsigned_8 ((Addr / 2**56) and 16#FF#);
   end Set_PRPS_Io;

   -- Send an Admin command and poll for completion.
   -- NVMe doorbell is a monotonic counter, NOT a queue index.
   -- Checks Phase Tag (P bit) and Status Field to distinguish success from error.
   SQ0_Tail  : Unsigned_32 := 0;

   procedure Admin_Send (SQ : in out Admin_SQ_Array; Success : out Boolean) is
      Cq_Off : constant Integer := (Integer (SQ0_Tail) rem 2) * 16;
      Status : Unsigned_32;
      Done   : Boolean := False;
   begin
      SQ0_Tail := SQ0_Tail + 1;
      -- Wrap doorbell for QEMU: tail must be < queue_size (2 entries)
      declare
         Db_Tail : constant Unsigned_32 :=
           Unsigned_32 (Integer (SQ0_Tail) rem 2);
      begin
         System.Machine_Code.Asm ("mfence", Volatile => True);
         Mmio_Write (16#1000#, Db_Tail);
      end;
      Success := False;

      -- Scan all 32 bytes of Admin CQ — find any completion
      for I in 1 .. 4_000_000 loop
         for J in 0 .. 31 loop
            if ACQ (J) /= 0 then
               -- Extract status field from the active CQ entry
               -- Status field lives in DW3 bytes 14-15 (byte 14 bit 0 = phase
               -- tag, bits 1-7 + byte 15 = SCT:SC). Bytes 12-13 are the CID.
               Status :=
                 Shift_Right (Unsigned_32 (ACQ (Cq_Off + 14)), 1) or
                 Shift_Left  (Unsigned_32 (ACQ (Cq_Off + 15)), 7);
               Success := (Status = 0);
               Done := True;
               exit;
            end if;
         end loop;
         exit when Done;
      end loop;

      if Success then
         -- Wrap CQ head doorbell for 2-entry queue
         declare
            Db_Head : constant Unsigned_32 :=
              Unsigned_32 (Integer (SQ0_Tail) rem 2);
         begin
            Mmio_Write (16#1004#, Db_Head);
         end;
      end if;
      ACQ := (others => 0);
   end Admin_Send;

   procedure Init_MMIO (MMIO_Base : Unsigned_64) is
      Cap_Hi  : Unsigned_32;
      Dstrd   : Unsigned_32;
      Success : Boolean;
      Msg_OK  : constant String := "[NVME] Init OK — queues ready";
      Msg_IO  : constant String := "[NVME] I/O queues created";
   begin
      MMIO := MMIO_Base;

      -- Read CAP:DSTRD to calculate doorbell stride
      Cap_Hi := Mmio_Read (16#0004#);
      Dstrd := Cap_Hi and 16#F#;
      DB_Stride := Shift_Left (1, 2 + Integer (Dstrd));

      -- Full controller reset: disable, wait, reconfigure, enable
      Mmio_Write (16#0014#, 0);  -- CC.EN=0
      -- Wait for controller to stop (RDY=0) with generous timeout
      for I in 1 .. 1_000_000 loop
         exit when (Mmio_Read (16#001C#) and 1) = 0;
      end loop;
      -- Small delay after stop
      for I in 1 .. 100_000 loop null; end loop;

      -- Reconfigure with OUR queue addresses
      SQ0_Tail := 0;
      Use_Ext_ACQ := False;

      -- Reset Admin SQ tail counter for fresh configuration
      SQ0_Tail := 0;

      Mmio_Write (16#0024#, 16#0001_0001#);  -- AQA: 2 entries each
      declare
         ASQ_Addr : constant Unsigned_64 := C_Addr (ASQ'Address);
         ACQ_Addr : constant Unsigned_64 := C_Addr (ACQ'Address);
      begin
         Mmio_Write (16#0028#, Unsigned_32 (ASQ_Addr and 16#FFFFFFFF#));
         Mmio_Write (16#002C#, 0);
         Mmio_Write (16#0030#, Unsigned_32 (ACQ_Addr and 16#FFFFFFFF#));
         Mmio_Write (16#0034#, 0);
      end;

      Mmio_Write (16#0014#, (4 * 2**20) or (6 * 2**16) or 1);
      for I in 1 .. 1_000_000 loop
         exit when (Mmio_Read (16#001C#) and 1) = 1;
      end loop;

      -- Create I/O CQ (QID=1, QSIZE=1 → 2 entries)
      declare
         Slot : constant Integer := (Integer (SQ0_Tail) rem 2) * 64;
      begin
         ASQ (Slot + 0) := 16#05#;   -- Opcode: Create I/O CQ
         ASQ (Slot + 40) := 1;        -- CDW10: QID=1 (byte 0)
         ASQ (Slot + 42) := 1;        -- CDW10: QSIZE=1 (byte 2)
         ASQ (Slot + 44) := 1;        -- CDW11: PC=1 (qflags bits 15:0)
         Set_PRPS (ASQ, Unsigned_32 (Slot) + 24, C_Addr (IOCQ'Address));
      end;

      -- Diagnostic: verify ACQ is zero before send
      if ACQ (12) /= 0 then
         declare
            Msg_Diag : constant String := "[NVME] ACQ not zero before send!";
         begin
            C_Putln (Msg_Diag'Address, Msg_Diag'Length);
         end;
      end if;

      Admin_Send (ASQ, Success);
      if not Success then
         -- Dump ACQ for diagnostics
         declare
            Msg_CF : constant String := "[NVME] Create I/O CQ FAILED";
         begin
            C_Putln (Msg_CF'Address, Msg_CF'Length);
            -- Check if any byte in ACQ changed
            if ACQ (0) /= 0 or ACQ (12) /= 0 then
               C_Putln (Msg_CF'Address, Msg_CF'Length);
            end if;
         end;
         return;
      end if;

      -- Create I/O SQ (QID=1, QSIZE=1 → 2 entries, linked to CQ1)
      declare
         Slot : constant Integer := (Integer (SQ0_Tail) rem 2) * 64;
      begin
         ASQ (Slot + 0) := 16#01#;   -- Opcode: Create I/O SQ
         ASQ (Slot + 40) := 1;        -- CDW10: QID=1 (byte 0)
         ASQ (Slot + 42) := 1;        -- CDW10: QSIZE=1 (byte 2)
         ASQ (Slot + 44) := 1;        -- CDW11: CQID=1 (bits 15:0)
         ASQ (Slot + 46) := 1;        -- CDW11: PC=1 (SQ flags, bit 16)
         Set_PRPS (ASQ, Unsigned_32 (Slot) + 24, C_Addr (IOSQ'Address));
      end;
      Admin_Send (ASQ, Success);
      if not Success then
         declare
            Msg_SF : constant String := "[NVME] Create I/O SQ FAILED";
         begin
            C_Putln (Msg_SF'Address, Msg_SF'Length); return;
         end;
      end if;

      Ready := True;
      C_Putln (Msg_IO'Address, Msg_IO'Length);
      C_Putln (Msg_OK'Address, Msg_OK'Length);
   end Init_MMIO;

   procedure Init is
      Info     : Schild_Pci_Scanner.Pci_Device_Info;
      Msg_Scan : constant String := "[NVME] Scanning PCI...";
      Msg_NF   : constant String := "[NVME] Not found";
   begin
      C_Putln (Msg_Scan'Address, Msg_Scan'Length);
      Info := Schild_Pci_Scanner.Find_Device (16#144D#, 16#A808#);
      if not Info.Found then
         Info := Schild_Pci_Scanner.Find_Device (16#1B36#, 16#0010#);
      end if;
      if not Info.Found then
         Info := Schild_Pci_Scanner.Find_Device (16#8086#, 16#5845#);
      end if;
      if not Info.Found then
         C_Putln (Msg_NF'Address, Msg_NF'Length); return;
      end if;

      MMIO := Unsigned_64 (Info.BAR0 and 16#FFFFFFF0#);
      C_Map_MMIO (MMIO and not 16#1FFFFF#);
      Init_MMIO (MMIO);
   end Init;

   function Is_Ready return Boolean is (Ready);

   -- Send Identify Controller command (CNS=1) via Admin SQ.
   -- Fills global Id_Buf and Id_Info with model + serial.
   procedure Do_Identify is
      Msg_Ident : constant String := "[NVME] Identify Controller sent";
      Msg_Done  : constant String := "[NVME] Identify completed";
   begin
      if not Ready then return; end if;

      -- Build Identify command in correct Admin SQ slot
      declare
         Slot : constant Integer := (Integer (SQ0_Tail) rem 2) * 64;
      begin
         ASQ (Slot + 0) := 16#06#;   -- Opcode: Identify
         ASQ (Slot + 40) := 1;        -- CDW10: CNS=1 (Identify Controller)
         Set_PRPS (ASQ, Unsigned_32 (Slot) + 24, C_Addr (Id_Buf'Address));
      end;
      C_Putln (Msg_Ident'Address, Msg_Ident'Length);

      declare
         Success : Boolean;
      begin
         Admin_Send (ASQ, Success);
      end;
      C_Putln (Msg_Done'Address, Msg_Done'Length);

      -- Parse Model Number (bytes 24-63 of Identify data)
      for I in 1 .. 40 loop
         declare
            C : constant Unsigned_8 := Id_Buf (24 + I - 1);
         begin
            Id_Info.Model (I) := (if C in 16#20# .. 16#7E#
                                  then Character'Val (C) else ' ');
         end;
      end loop;

      -- Parse Serial Number (bytes 4-23)
      for I in 1 .. 20 loop
         declare
            C : constant Unsigned_8 := Id_Buf (4 + I - 1);
         begin
            Id_Info.Serial (I) := (if C in 16#20# .. 16#7E#
                                    then Character'Val (C) else ' ');
         end;
      end loop;

      Id_Info.Valid := True;
   end Do_Identify;

   function Get_Info return Identify_Info is
   begin
      if not Id_Info.Valid and then Ready then
         Do_Identify;
      end if;
      return Id_Info;
   end Get_Info;

   -- Send an NVM command via I/O Submission Queue (QID=1, 2 entries)
   SQ1_Tail : Unsigned_32 := 0;
   -- Bounded completion-poll: a hung controller must not hang the kernel.
   IO_Timeout_Limit : constant := 4_000_000;

   procedure Io_Send (Success : out Boolean) is
      Sq_Db : constant Unsigned_32 := 16#1000# + 2 * DB_Stride;     -- SQ1
      Cq_Db : constant Unsigned_32 := 16#1000# + 3 * DB_Stride;     -- CQ1
      Cq_Off : constant Integer := (Integer (SQ1_Tail) rem 2) * 16;
      Status : Unsigned_32;
      Done   : Boolean := False;
   begin
      if not Ready then Success := False; return; end if;
      SQ1_Tail := SQ1_Tail + 1;
      -- Wrap SQ doorbell for 2-entry I/O queue (QEMU requires tail < size)
      declare
         Db_Tail : constant Unsigned_32 :=
           Unsigned_32 (Integer (SQ1_Tail) rem 2);
      begin
         System.Machine_Code.Asm ("mfence", Volatile => True);
         Mmio_Write (Sq_Db, Db_Tail);
      end;

      Success := False;
      for I in 1 .. IO_Timeout_Limit loop
         for J in 0 .. 31 loop
            if IOCQ (J) /= 0 then
               Status :=
                 Shift_Left  (Unsigned_32 (IOCQ (Cq_Off + 13)), 8) or
                 Unsigned_32 (IOCQ (Cq_Off + 12));
               Success := (Status = 0);
               Done := True;
               exit;
            end if;
         end loop;
         exit when Done;
      end loop;

      if not Done then
         declare
            Msg_Tmo : constant String := "[NVMe] I/O completion timeout (controller hang?)";
         begin
            C_Putln (Msg_Tmo'Address, Msg_Tmo'Length);
         end;
      elsif not Success then
         declare
            Msg_Err : constant String := "[NVMe] I/O command FAILED (status non-zero)";
         begin
            C_Putln (Msg_Err'Address, Msg_Err'Length);
         end;
      end if;

      if Success then
         -- Wrap I/O CQ head doorbell for 2-entry queue
         declare
            Db_Head : constant Unsigned_32 :=
              Unsigned_32 (Integer (SQ1_Tail) rem 2);
         begin
            Mmio_Write (Cq_Db, Db_Head);
         end;
      end if;
      IOCQ := (others => 0);
   end Io_Send;

   -- Read one 512-byte block from LBA into RW_Buf
   procedure Read_Block (LBA : Unsigned_64; Success : out Boolean) is
      Slot_Base : constant Integer := (Integer (SQ1_Tail) rem 2) * 64;
   begin
      IOSQ := (others => 0);
      IOSQ (Slot_Base + 0) := 16#02#;  -- Opcode: NVM Read
      IOSQ (Slot_Base + 4) := 1;        -- NSID=1
      Set_PRPS_Io (IOSQ, Unsigned_32 (Slot_Base) + 24, C_Addr (RW_Buf'Address));
      IOSQ (Slot_Base + 40) := Unsigned_8 ( LBA         and 16#FF#);
      IOSQ (Slot_Base + 41) := Unsigned_8 ((LBA / 2**8)  and 16#FF#);
      IOSQ (Slot_Base + 42) := Unsigned_8 ((LBA / 2**16) and 16#FF#);
      IOSQ (Slot_Base + 43) := Unsigned_8 ((LBA / 2**24) and 16#FF#);
      IOSQ (Slot_Base + 48) := 0;  -- NLB = 0 → 1 block
      Io_Send (Success);
   end Read_Block;

   -- Write one 512-byte block from RW_Buf to LBA
   procedure Write_Block (LBA : Unsigned_64; Success : out Boolean) is
      Slot_Base : constant Integer := (Integer (SQ1_Tail) rem 2) * 64;
   begin
      IOSQ := (others => 0);
      IOSQ (Slot_Base + 0) := 16#01#;  -- Opcode: NVM Write
      IOSQ (Slot_Base + 4) := 1;
      Set_PRPS_Io (IOSQ, Unsigned_32 (Slot_Base) + 24, C_Addr (RW_Buf'Address));
      IOSQ (Slot_Base + 40) := Unsigned_8 ( LBA         and 16#FF#);
      IOSQ (Slot_Base + 41) := Unsigned_8 ((LBA / 2**8)  and 16#FF#);
      IOSQ (Slot_Base + 42) := Unsigned_8 ((LBA / 2**16) and 16#FF#);
      IOSQ (Slot_Base + 43) := Unsigned_8 ((LBA / 2**24) and 16#FF#);
      IOSQ (Slot_Base + 48) := 0;
      Io_Send (Success);
   end Write_Block;

   function Get_Buffer return Block_Buf is
   begin
      return RW_Buf;
   end Get_Buffer;

   procedure Fill_Buffer (Data : Block_Buf) is
   begin
      RW_Buf := Data;
   end Fill_Buffer;

   -- Boot-log capture buffer (filled by the C runtime, runtime_stubs.c)
   Log_Buf : array (0 .. 8191) of Interfaces.Unsigned_8;
   pragma Import (C, Log_Buf, "schild_log_buf");
   Log_Len : Interfaces.Unsigned_32;
   pragma Import (C, Log_Len, "schild_log_len");

   -- Persist the captured boot log to NVMe LBA 2000+ (free GPT gap).
   procedure Flush_Log_To_Nvme is
      Buf : Block_Buf;
      Off : Interfaces.Unsigned_32 := 0;
      Lba : Interfaces.Unsigned_64 := 2000;
      Ok  : Boolean;
   begin
      if not Ready then
         return;
      end if;
      while Off < Log_Len loop
         Buf := (others => 0);
         for J in 0 .. 511 loop
            exit when Off + Interfaces.Unsigned_32 (J) >= Log_Len;
            Buf (J) := Log_Buf (Integer (Off) + J);
         end loop;
         Fill_Buffer (Buf);
         Write_Block (Lba, Ok);
         if not Ok then
            declare
               Msg_WFail : constant String := "[NVME] Flush write FAILED";
            begin
               C_Putln (Msg_WFail'Address, Msg_WFail'Length);
            end;
         end if;
         Lba := Lba + 1;
         Off := Off + 512;
      end loop;
   end Flush_Log_To_Nvme;

end Schild_Nvme;

