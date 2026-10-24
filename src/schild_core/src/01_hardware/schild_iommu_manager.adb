with System.Machine_Code;     use System.Machine_Code;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces;              use Interfaces;
with Schild_Acpi_Tables;

package body Schild_Iommu_Manager with
  SPARK_Mode => Off --  MMIO register I/O / inline asm: outside SPARK's model.
is

   subtype U64 is Unsigned_64;
   subtype U32 is Unsigned_32;

   --  ── Intel VT-d (DMAR) data structures ──────────────────────────────────
   --  Root table: 256 x 64-bit entries, 4 KiB aligned.
   Root   : array (0 .. 255) of U64 with Alignment => 4096;
   --  Context table: 256 x 128-bit entries (two parallel 64-bit arrays).
   Ctx_Lo : array (0 .. 255) of U64 with Alignment => 4096;
   Ctx_Hi : array (0 .. 255) of U64 with Alignment => 4096;
   --  Four-level I/O page table: single PML4/PDPT nodes + full PD + full PT.
   Pml4 : U64                  with Alignment => 4096;
   Pdpt : U64                  with Alignment => 4096;
   Pd   : array (0 .. 511) of U64 with Alignment => 4096;
   Pt   : array (0 .. 511) of U64 with Alignment => 4096;

   --  Page-table / root / context flags.
   P_Flag  : constant U64 := 1;   -- present
   RW_Flag : constant U64 := 2;   -- read/write

   --  DMA remapping unit MMIO base (placeholder — read from DMAR ACPI on T580).
   Dmar_Base : constant := 16#FED9_0000#;

   TE_Bit   : constant U32 := 2**24;   -- translation enable (GCMD/GSTS)
   SRTP_Bit : constant U32 := 2**30;   -- set root-table pointer (GCMD)
   RTPS_Bit : constant U32 := 2**31;   -- root-table pointer status (GSTS)
   TES_Bit  : constant U32 := 2**24;   -- translation-enable status (GSTS)

   --  Volatile MMIO registers overlaid on the DMAR register block.
   Dmar_Gcmd   : U32 with Volatile;
   Dmar_Gsts   : U32 with Volatile;
   Dmar_Rtaddr : U32 with Volatile;
   for Dmar_Gcmd'Address   use To_Address (Integer_Address (Dmar_Base + 16#18#));
   for Dmar_Gsts'Address   use To_Address (Integer_Address (Dmar_Base + 16#1C#));
   for Dmar_Rtaddr'Address use To_Address (Integer_Address (Dmar_Base + 16#20#));

   --  Physical address of a 4 KiB-aligned static table.
   function Phys_Addr (A : System.Address) return U64 is
     (U64 (To_Integer (A)));

   --  Busy-wait until the GSTS bit(s) in Mask reach the expected state.
   procedure Wait_Gsts (Mask : U32; Set : Boolean) is
      R : U32;
   begin
      for I in 1 .. 1_000_000 loop
         R := Dmar_Gsts;
         exit when Set = ((R and Mask) /= 0);
         Asm (Template => "pause", Volatile => True);
      end loop;
   end Wait_Gsts;

   --  ── Public operations ──────────────────────────────────────────────────

   procedure Flush_Iommu_Cache is
   begin
      Asm (Template => "mfence", Volatile => True);
   end Flush_Iommu_Cache;

   procedure Parse_Dmar_Table
     (Dmar     : in     Dmar_Byte_Array;
      Reg_Base :    out Unsigned_64;
      Success  :    out Boolean)
   is
   begin
      --  Delegate to the pure, host-testable ACPI parser (which also fixes the
      --  DRHD offset bug: register base at +8, structures at +48).
      Schild_Acpi_Tables.Parse_Dmar_Table (Dmar, Reg_Base, Success);
   end Parse_Dmar_Table;

   procedure Block_Device (Device_ID : in Device_Id_Type) is
      Dev  : constant U64 := (U64 (Device_ID) / 256) mod 32;  -- device field
      Func : constant U64 := U64 (Device_ID) mod 256;         -- function field
      Idx  : constant Integer := Integer (Dev * 8 + Func);
   begin
      Ctx_Lo (Idx) := 0;   -- not-present => hardware block
      Ctx_Hi (Idx) := 0;
      Flush_Iommu_Cache;
   end Block_Device;

   procedure Initialize is
      Root_Pa : constant U64 := Phys_Addr (Root'Address);
      Ctx_Pa  : constant U64 := Phys_Addr (Ctx_Lo'Address);
      Pd_Pa   : constant U64 := Phys_Addr (Pd'Address);
      Pt_Pa   : constant U64 := Phys_Addr (Pt'Address);
      Pml4_Pa : constant U64 := Phys_Addr (Pml4'Address);
      --  NIC context-table index: device 31, function 6 => 31*8 + 6.
      Nic_Idx : constant Integer := 31 * 8 + 6;
   begin
      --  1) Zero all translation structures.
      Root   := (others => 0);
      Ctx_Lo := (others => 0);
      Ctx_Hi := (others => 0);
      Pml4 := 0;  Pdpt := 0;  Pd := (others => 0);  Pt := (others => 0);

      --  2) Build the I/O page table: identity-map ONLY the shared window.
      --     Shared window = pages 0x520..0x529 => PT indices 288..297.
      for I in 0 .. 9 loop
         Pt (288 + I) := U64 (Shared_Base) + U64 (I) * 16#1000# + P_Flag + RW_Flag;
      end loop;
      Pd (2) := Pt_Pa + P_Flag + RW_Flag;          -- PD entry 2 => PT (2 MiB)
      Pdpt   := Pd_Pa + P_Flag + RW_Flag;          -- PDPT entry 0 => PD (1 GiB)
      Pml4   := Phys_Addr (Pdpt'Address) + P_Flag + RW_Flag;  -- PML4 => PDPT

      --  3) Context entry for the NIC: present, translated, ASR = PML4.
      Ctx_Lo (Nic_Idx) := Pml4_Pa + 1;   -- P=1, translation type 0 (translated)
      Ctx_Hi (Nic_Idx) := 0;             -- domain 0

      --  4) Root entry for bus 0 => context table (all other buses absent).
      Root (0) := Ctx_Pa + 1;            -- present

      --  5) Program the DMA remapping unit.
      Dmar_Gcmd := Dmar_Gcmd and (not TE_Bit);     -- disable translation
      Wait_Gsts (TES_Bit, False);
      Dmar_Rtaddr := U32 (Root_Pa and 16#FFFF_FFFF#);  -- root-table pointer
      Dmar_Gcmd := Dmar_Gcmd or SRTP_Bit;           -- set root-table pointer
      Wait_Gsts (RTPS_Bit, True);
      Dmar_Gcmd := Dmar_Gcmd or TE_Bit;             -- enable translation
      Wait_Gsts (TES_Bit, True);
      Flush_Iommu_Cache;
   end Initialize;

   procedure Map_Device_Page
     (Device_ID   : in     Device_Id_Type;
      Source_Page : in     Long_Integer;
      Target_Page : in     Long_Integer;
      Success     :    out Boolean)
   is
      Page_No : constant Integer := Integer (Target_Page / 16#1000#);
      Pd_Idx  : constant Integer := Page_No / 512;
      Pt_Idx  : constant Integer := Page_No mod 512;
   begin
      --  Only the shared-window policy is wired: identity-map a page into the
      --  I/O page table. The NIC context entry already references the PT.
      if Page_No < 0 or else Pd_Idx /= 2 then
         Success := False;
         return;
      end if;
      Pt (Pt_Idx) := U64 (Target_Page) + P_Flag + RW_Flag;
      Flush_Iommu_Cache;
      Success := True;
   end Map_Device_Page;

end Schild_Iommu_Manager;
