-- Schild TCB Kernel Logic — PIT-driven preemptive scheduler (IRQ0 → vector 0x20).
--
-- Architecture: PIT channel 0 (100 Hz, periodic) → PIC master IRQ0 → vector 0x20.
-- Handler (irq0_tmr) sends PIC EOI, calls Tick() for scheduling, returns via iretq.
-- Main loop: sti; loop { hlt; poll e1000e; } — wakes on every PIT tick (~10ms).
-- LAPIC is masked entirely to prevent spurious interrupts; IOAPIC is masked.
--
-- SPARK note: Run loop is infinite (kernel never returns), SPARK_Mode => Off.
--
with Schild_Scheduler; with Schild_Timer; with Schild_Uart_Driver; with Schild_MTF;
with Schild_E1000e; with Interfaces;
with System.Machine_Code;

package body Schild_Kernel_Logic with SPARK_Mode => Off is
   use Schild_Scheduler; use Schild_Timer; use Interfaces;

   Sched  : Scheduler_Type;
   Timer  : Timer_Hardware_Record;
   Ticks  : Tick_Count_Type := 0;
   Active : Boolean := False;

   -- PIC/PIT/IDT initialization (see interrupt_handlers.c)
   procedure C_Apic_Init;    pragma Import (C, C_Apic_Init,    "schild_apic_init");
   procedure C_Pic_Remap;    pragma Import (C, C_Pic_Remap,    "schild_pic_remap");
   procedure C_Pic_Unmask_0; pragma Import (C, C_Pic_Unmask_0, "schild_pic_unmask_irq0");
   procedure C_Pit_Init;     pragma Import (C, C_Pit_Init,     "schild_pit_init");

   -- LAPIC/IOAPIC masking (prevent spurious interrupts)
   procedure C_Lapic_Mask;  pragma Import (C, C_Lapic_Mask,  "schild_lapic_mask_all");
   procedure C_Ioapic_Mask; pragma Import (C, C_Ioapic_Mask, "schild_ioapic_mask_all");

   -- IDT loading
   procedure C_Idt_Raw;      pragma Import (C, C_Idt_Raw,      "schild_idt_init_raw");
   procedure C_Verify_Idt;   pragma Import (C, C_Verify_Idt,   "schild_verify_idt");

   -- Interrupt flag control (sti/hlt/cli — x86_64 bare-metal)
   procedure C_Sti; pragma Import (C, C_Sti, "schild_sti");
   procedure C_Hlt; pragma Import (C, C_Hlt, "schild_hlt");
   procedure C_Cli; pragma Import (C, C_Cli, "schild_cli");

   -- e1000e RX pending flag (set by interrupt handler, cleared by main loop)
   C_Rx_Pending : Unsigned_32;
   pragma Import (C, C_Rx_Pending, "e1000e_rx_pending");

   procedure Init is
   begin
      Schild_Uart_Driver.Put_Line ("[LOGIC] Initializing preemptive scheduler...");

      -- Initialize scheduler: all slots empty, slot 1 as bootstrap task
      Sched.Current_Task := 0;
      for I in Valid_Task_Id loop
         Sched.Tasks (I).State := Task_Empty;
         Sched.Tasks (I).Priority := 0;
      end loop;
      Sched.Tasks (1).State := Task_Ready;
      Sched.Tasks (1).Priority := 0;
      Sched.Current_Task := 1;

      Timer.Is_Running := True;
      Timer.System_Ticks := 0;

      -- Hardware interrupt setup (PIT + PIC path):
      --   0. Enable LAPIC (spurious vector 0xFF) — required for LINT0 ExtINT
      --   1. Remap PIC: master IRQ0-7 → vectors 0x20-0x27, slave → 0x28-0x2F
      --   2. Init PIT channel 0: ~100 Hz (~10ms period, divisor 11932)
      --   3. Unmask IRQ0 on master PIC (PIT tick delivery)
      --   4. Configure LAPIC: LINT0 ExtINT + mask all other LVT
      --   5. Mask all IOAPIC redirection entries
      --   6. Load IDT from schild_interrupt_vectors
      C_Apic_Init;
      C_Pic_Remap;
      C_Pit_Init;
      C_Pic_Unmask_0;
      C_Lapic_Mask;
      C_Ioapic_Mask;
      C_Idt_Raw;
      C_Verify_Idt;

      Active := True;
      Schild_Uart_Driver.Put_Line ("[LOGIC] Preemptive scheduler ready (PIT IRQ0, sti/hlt)");
   end Init;

   procedure Tick is
      P    : Schild_MTF.Partition_Id;
      Next : Task_Id;
   begin
      if not Active then return; end if;
      -- SPARK-proved atomic tick: no drift, no overflow.
      Update_System_Tick (Timer);
      Ticks := Timer.System_Ticks;
      -- Two-level schedule (ARINC 653):
      --   level 1 -- MTF selects the active partition (static, cyclic);
      --   level 2 -- priority selects the task within that partition.
      P := Schild_MTF.Partition_For_Tick (Schild_MTF.Default_Schedule, Ticks);
      Next := Find_Next_Task_In_Partition (Sched, P);
      if Next > 0 then
         Sched.Current_Task := Next;
      else
         Sched.Current_Task := 0;  -- idle: no ready task in this partition
      end if;
   end Tick;

   procedure Run is
      Rx_Buf : Schild_E1000e.Unsigned_8_Array (0 .. 2047);
      Rx_Len : Interfaces.Unsigned_16;
      Tick_Threshold : constant Tick_Count_Type := 100;
      Next_Print     : Tick_Count_Type := Tick_Threshold;
   begin
      -- Enable maskable interrupts (IF=1).
      C_Sti;

      -- Idle loop: halt until next PIT timer interrupt (~10ms).
      -- Handler (irq0_tmr): saves XMM, sends EOI, calls Tick(), restores XMM, iretq.
      -- Heartbeat + e1000e poll on each wake.
      loop
         C_Hlt;
         -- Heartbeat every ~100 ticks (~1 sec)
         if Ticks >= Next_Print then
            Schild_Uart_Driver.Put_Line ("[TICK] Scheduler heartbeat");
            Next_Print := Ticks + Tick_Threshold;
         end if;
         -- Process e1000e RX via interrupt flag (set by e1000e_irq_handler)
         if C_Rx_Pending /= 0 then
            C_Rx_Pending := 0;
            while Schild_E1000e.Poll_Rx (Rx_Buf, Rx_Len) loop
               Schild_Uart_Driver.Put_Line ("[E1000E] RX packet received (IRQ)");
               exit;  -- One packet per wake
            end loop;
         end if;
      end loop;
   end Run;

   function Get_Ticks return Tick_Count_Type is (Ticks);
   function Is_Active return Boolean is (Active);
end Schild_Kernel_Logic;
