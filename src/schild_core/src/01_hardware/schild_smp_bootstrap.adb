-- Schild TCB SMP Bootstrap — full, inline asm for LAPIC
with System; with Interfaces; with System.Machine_Code; with Schild_Nvme;

package body Schild_Smp_Bootstrap with SPARK_Mode => Off is
   use Interfaces;
   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   procedure C_Phys_Write (Addr, Value : Unsigned_64);
   pragma Import (C, C_Phys_Write, "schild_phys_write64");

   function C_Rdtsc return Unsigned_64;
   pragma Import (C, C_Rdtsc, "schild_rdtsc");

   Max_Cpus : constant := 8;
   Cpu_Count : Unsigned_32 := 1;
   --  Written concurrently by every AP in Ap_Entry and read by the BSP's wait
   --  loop: must not be cached in a register. (The increment itself is a benign
   --  non-atomic RMW; a lost increment only yields an "incomplete" message, and
   --  APs come online sequentially with per-AP delays so collisions are rare.)
   pragma Volatile (Cpu_Count);
   Bsp_Apic  : Unsigned_8 := 0;
   type Ap_Stack_Array is array (0 .. 8191) of Unsigned_8;
   Ap_Stacks : array (1 .. Max_Cpus - 1) of Ap_Stack_Array;

   function Addr_To_U64 (A : System.Address) return Unsigned_64;
   pragma Import (C, Addr_To_U64, "schild_ptr_to_u64");

   function Get_CR3 return Unsigned_64 is
      V : Unsigned_64;
   begin
      System.Machine_Code.Asm ("movq %%cr3, %0",
        Outputs => Unsigned_64'Asm_Output ("=r", V), Volatile => True);
      return V;
   end Get_CR3;

   function Get_Apic_Id return Unsigned_8 is
      Id : Unsigned_32;
   begin
      System.Machine_Code.Asm (
        "movl $0xFEE00020, %%eax;" &
        "movl (%%eax), %%eax;"    &
        "shrl $24, %%eax;",
        Outputs => Unsigned_32'Asm_Output ("=a", Id), Volatile => True);
      return Unsigned_8 (Id and 16#FF#);
   end Get_Apic_Id;

   procedure Lapic_Write (Off : Unsigned_32; Val : Unsigned_32) is
   begin
      System.Machine_Code.Asm (
        "movl $0xFEE00000, %%eax;" &
        "addl %0, %%eax;"          &
        "movl %1, (%%eax)",
        Inputs => (Unsigned_32'Asm_Input ("r", Off),
                    Unsigned_32'Asm_Input ("r", Val)),
        Clobber => "eax", Volatile => True);
   end Lapic_Write;

   procedure Phys_Write64 (PA : Unsigned_64; Val : Unsigned_64) is
   begin
      C_Phys_Write (PA, Val);
   end Phys_Write64;

   -- Copy_Trampoline delegated to C (avoids GNAT Addr_To_U64 issues)
   procedure Copy_Trampoline is
      procedure C_Copy_Trampoline;
      pragma Import (C, C_Copy_Trampoline, "schild_copy_trampoline");
   begin
      C_Copy_Trampoline;
   end Copy_Trampoline;

   procedure Init is
      Msg_SMP  : constant String := "[SMP]   Starting AP cores...";
      Msg_Done : constant String := "[SMP]   All APs started";
      Msg_Part : constant String := "[SMP]   APs started: incomplete";
      -- Fixed trampoline destination addresses (0x8000 + slot offset):
      Dst_PML4  : constant Unsigned_64 := 16#80D0#;
      Dst_Stack : constant Unsigned_64 := 16#80D8#;
      Dst_CpuId : constant Unsigned_64 := 16#80E0#;
      Dst_Entry : constant Unsigned_64 := 16#80E8#;
   begin
      Bsp_Apic := Get_Apic_Id;
      Copy_Trampoline;
      declare
         Cr3_Val : constant Unsigned_64 := Get_CR3;
      begin
         Phys_Write64 (Dst_PML4, Cr3_Val);
      end;
      C_Putln (Msg_SMP'Address, Msg_SMP'Length);
      Schild_Nvme.Flush_Log_To_Nvme;
      for Cpu in 2 .. Max_Cpus loop
         declare
            Test_Id : constant Unsigned_8 := Unsigned_8 (Cpu - 1);
         begin
            if Test_Id /= Bsp_Apic then
               Phys_Write64 (Dst_CpuId, Unsigned_64 (Test_Id));
               Phys_Write64 (Dst_Entry, Addr_To_U64 (Ap_Entry'Address));
               Phys_Write64 (Dst_Stack,
                 Addr_To_U64 (Ap_Stacks (Cpu - 1)'Address) + 8192);
               Start_Ap (Test_Id, Cpu);
               for D in 1 .. 500_000 loop null; end loop;
               Schild_Nvme.Flush_Log_To_Nvme;
            end if;
         end;
      end loop;
      -- Wait for all APs to actually come online (Ap_Entry increments Cpu_Count).
      -- Real-time TSC timeout instead of a magic iteration count: the old
      -- 50_000_000 loop expired before the APs finished starting, so
      -- "All APs started" was printed prematurely.
      declare
         Ap_Wait_Ticks : constant Unsigned_64 := 10_000_000_000;  -- ~5 s @ 2 GHz
         Tsc_Start     : constant Unsigned_64 := C_Rdtsc;
      begin
         loop
            exit when Cpu_Count >= Unsigned_32 (Max_Cpus);
            exit when C_Rdtsc - Tsc_Start > Ap_Wait_Ticks;
         end loop;
      end;
      if Cpu_Count >= Unsigned_32 (Max_Cpus) then
         C_Putln (Msg_Done'Address, Msg_Done'Length);
      else
         C_Putln (Msg_Part'Address, Msg_Part'Length);
      end if;
      Schild_Nvme.Flush_Log_To_Nvme;
   end Init;

   procedure Start_Ap (Apic_Id : Unsigned_8; Cpu_Idx : Positive) is
      Vector : constant Unsigned_32 := 16#08#;  -- 0x8000 / 4096
   begin
      --  INIT (assert): level-triggered INIT to the target AP.
      Lapic_Write (16#310#, Shift_Left (Unsigned_32 (Apic_Id), 24));
      Lapic_Write (16#300#, 16#C500#);
      for D in 1 .. 500_000 loop null; end loop;
      --  INIT (deassert): the MP protocol requires releasing INIT before the
      --  Startup IPI. Without it the AP can stay in the INIT-asserted state and
      --  never take the SIPI — observed as an intermittent "stuck at Core online".
      Lapic_Write (16#310#, Shift_Left (Unsigned_32 (Apic_Id), 24));
      Lapic_Write (16#300#, 16#C400#);
      for D in 1 .. 500_000 loop null; end loop;
      --  SIPI (Startup IPI), sent twice for reliability.
      Lapic_Write (16#310#, Shift_Left (Unsigned_32 (Apic_Id), 24));
      Lapic_Write (16#300#, 16#4600# or Vector);
      for D in 1 .. 500_000 loop null; end loop;
      Lapic_Write (16#310#, Shift_Left (Unsigned_32 (Apic_Id), 24));
      Lapic_Write (16#300#, 16#4600# or Vector);
   end Start_Ap;

   procedure Ap_Entry (Cpu_Id : Unsigned_32) is
      Msg_Online : constant String := "[SMP]   Core online";
      Msg_Beat   : constant String := "[SMP]   AP heartbeat";
      Counter : Unsigned_32 := 0;
   begin
      -- Enable local APIC (Spurious Interrupt Vector, offset 0xF0)
      System.Machine_Code.Asm (
        "movl $0xFEE000F0, %%eax;" &
        "movl $0x1FF, (%%eax)",
        Volatile => True, Clobber => "eax,memory");
      C_Putln (Msg_Online'Address, Msg_Online'Length);
      Cpu_Count := Cpu_Count + 1;

      -- Work loop: compute SHA-256-like workload, report heartbeat
      loop
         Counter := Counter + 1;
         -- Simulated crypto workload (modular multiply-add)
         for J in 1 .. 10_000 loop
            Counter := (Counter * 16#9E3779B9#) + 16#6A09E667#;
         end loop;
         -- Heartbeat every ~100K iterations
         if (Counter and 16#3FFF_FFFF#) = 0 then
            C_Putln (Msg_Beat'Address, Msg_Beat'Length);
            -- Brief HLT to let BSP run
            System.Machine_Code.Asm ("hlt", Volatile => True);
         end if;
      end loop;
   end Ap_Entry;

   function Get_Cpu_Count return Unsigned_32 is (Cpu_Count);
   function Get_Bsp_Apic_Id return Unsigned_8 is (Bsp_Apic);
end Schild_Smp_Bootstrap;
