-- Schild TCB NVMe Driver — I/O Queues + Read/Write.
-- Supports Samsung SM981 (T580) and QEMU NVMe.
with System; with Interfaces;

package Schild_Nvme with SPARK_Mode => Off is
   procedure Init;
   -- Initialize the controller with a pre-mapped MMIO base (Ring 3: the root
   -- task maps the NVMe BAR0 and passes its virtual address; Ring 0: identity-
   -- mapped physical BAR0). Skips the PCI scan + map_mmio_2mb.
   procedure Init_MMIO (MMIO_Base : Interfaces.Unsigned_64);
   function Is_Ready return Boolean;

   type Identify_Info is record
      Model  : String (1 .. 40);
      Serial : String (1 .. 20);
      Valid  : Boolean := False;
   end record;
   function Get_Info return Identify_Info;

   type Block_Buf is array (0 .. 511) of Interfaces.Unsigned_8;

   -- Read/Write single 512-byte blocks via I/O queues
   procedure Read_Block  (LBA : Interfaces.Unsigned_64; Success : out Boolean);
   procedure Write_Block (LBA : Interfaces.Unsigned_64; Success : out Boolean);
   function  Get_Buffer return Block_Buf;
   -- Fill the internal write buffer (avoid copy-on-return issue)
   procedure Fill_Buffer (Data : Block_Buf);

   -- Persist the captured boot log (schild_log_buf/schild_log_len) to NVMe
   -- LBA 2000+ (free GPT gap). Exposed so any driver can flush progress.
   procedure Flush_Log_To_Nvme;
end Schild_Nvme;
