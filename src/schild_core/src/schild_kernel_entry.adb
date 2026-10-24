-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- Schild TCB Full MLS Audit + seL4 IPC + Framebuffer

with System;
with System.Machine_Code;
with Interfaces;
with Schild_Kernel_State;
with Schild_Process_Manager;
with Schild_Framebuffer;
with Schild_Server_Init;      --  Server policy self-test.
with Schild_Server_Security_Policy; --  MLS Bell-LaPadula policy.
with Schild_Interrupt_Init;   --  Install IDT/IRQ handlers.
with Schild_Net_Init;         --  Network stack (firewall/filter/limiter).
with Schild_Net_Stack;        -- Stage 7.9: TCP/IP + HTTP dispatcher
with Schild_E1000e;           -- Driver Intel e1000e / I219-V
with Schild_Nvme;
with Schild_Schild_Fs;              -- NVMe driver
with Schild_Smp_Bootstrap;     -- SMP multi-core bootstrap
with Schild_Kernel_Logic;    --  Fallback kernel demo loop.

procedure Schild_Kernel_Entry
  (Multiboot_Info : System.Address;
   Fb_Addr        : System.Address;
   Fb_Width       : Interfaces.Unsigned_32;
   Fb_Height      : Interfaces.Unsigned_32;
   Fb_Pitch       : Interfaces.Unsigned_32;
   Fb_Bpp         : Interfaces.Unsigned_32)
is
   use Schild_Process_Manager;
   -- [SEL4 Stage 3] kernel_end address via safe C helper
   function Get_Kernel_End return Interfaces.Unsigned_64;
   pragma Import (C, Get_Kernel_End, "schild_get_kernel_end");


   procedure C_Puts  (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Puts,  "schild_uart_puts");
   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");
   procedure C_Kbd_Leds (Leds : Interfaces.Unsigned_8);
   pragma Import (C, C_Kbd_Leds, "schild_kbd_leds");

   -- [SEL4 Stage 3] seL4 microkernel launch init
   function Sel4_Launch_Init
     (Multiboot_Info_Addr : System.Address;
      Kernel_End_Addr     : Interfaces.Unsigned_64) return Integer;
   pragma Import (C, Sel4_Launch_Init, "schild_sel4_launch_init");

   -- Hardware timestamp counter (RDTSC) for real-time timeouts.
   function C_Rdtsc return Interfaces.Unsigned_64;
   pragma Import (C, C_Rdtsc, "schild_rdtsc");

   -- e1000e IRQ path (bare-metal only): enable LAPIC, load the C raw IDT
   -- (wires vector 0x30 -> e1000e_irq_handler), enable maskable interrupts.
   procedure C_Apic_Init; pragma Import (C, C_Apic_Init, "schild_apic_init");
   procedure C_Idt_Raw;   pragma Import (C, C_Idt_Raw,   "schild_idt_init_raw");
   procedure C_Sti;       pragma Import (C, C_Sti,       "schild_sti");

   Sel4_Result : Integer;


   Root_Pid   : Process_Id;
   Status     : Proc_Status;

   Msg_Boot      : constant String := "[BOOT] Schild TCB MLS audit";
   Msg_Fb        : constant String := "[STAGE] framebuffer initialized";
   Msg_Idt       : constant String := "[STAGE] IDT initialized";
   Msg_Irq_On    : constant String := "[IRQ] e1000e IRQ-driven RX enabled";
   Msg_Sel4_Fail : constant String := "[SEL4] Module not found — continuing standalone";
   Msg_T1_OK   : constant String := "[AUDIT] Test1 Root: PASS";
   Msg_T1_FAIL : constant String := "[AUDIT] Test1 Root: FAIL";
   Msg_T2_OK   : constant String := "[AUDIT] Test2 SameLevel: PASS";
   Msg_T2_FAIL : constant String := "[AUDIT] Test2 SameLevel: FAIL";
   Msg_T3_OK   : constant String := "[AUDIT] Test3 CrossLevel: PASS";
   Msg_T3_FAIL : constant String := "[AUDIT] Test3 CrossLevel: FAIL";
   Msg_T4a_OK  : constant String := "[AUDIT] Test4 Terminate: PASS";
   Msg_T4a_FAIL: constant String := "[AUDIT] Test4 Terminate: FAIL";
   Msg_T4b_OK  : constant String := "[AUDIT] Test4 Reap: PASS";
   Msg_T4b_FAIL: constant String := "[AUDIT] Test4 Reap: FAIL";
   Msg_T5_OK   : constant String := "[AUDIT] Test5 MLS Terminate: PASS";
   Msg_T5_FAIL : constant String := "[AUDIT] Test5 MLS Terminate: FAIL";
   Msg_Done    : constant String := "[AUDIT] MLS audit complete";
   Msg_CRLF    : constant String := (1 => ASCII.CR, 2 => ASCII.LF);
begin
   C_Kbd_Leds (16#02#);  --  NumLock = Ada kernel entry reached

   -- Initialise the framebuffer console FIRST so the early NVMe log is
   -- visible on screen (no serial console on the T580).
   Schild_Framebuffer.Init_Fb (Fb_Addr, Fb_Width, Fb_Height, Fb_Pitch, Fb_Bpp);
   C_Putln (Msg_Fb'Address, Msg_Fb'Length);

   -- ====== NVMe driver initialization (T580: Samsung SM981) ======
   -- Moved FIRST: on the T580 there is no serial/VGA console, so the NVMe log
   -- is the ONLY observable channel. This proves the kernel booted and persists
   -- the boot log before anything downstream (framebuffer/e1000e) can hang.
   Schild_Nvme.Init;
   if Schild_Nvme.Is_Ready then
      declare
         Info : constant Schild_Nvme.Identify_Info := Schild_Nvme.Get_Info;
      begin
         C_Putln (Info.Model'Address, 40);
         C_Putln (Info.Serial'Address, 20);
      end;

      -- P6: Read LBA 2000 → write test pattern → read back & verify.
      -- NOTE: LBA 2000 is the free GPT gap (before the first partition);
      -- never write to LBA 0/1 (protective MBR / primary GPT header) on a real disk.
      declare
         Success : Boolean;
         Msg_Rd : constant String := "[NVME] Read LBA 2000 OK";
         Msg_Wr : constant String := "[NVME] Write LBA 2000 OK";
         Msg_Vf : constant String := "[NVME] Verify OK";
         Msg_Err: constant String := "[NVME] Verify FAIL";
         Buf : Schild_Nvme.Block_Buf;
         use type Interfaces.Unsigned_8;
      begin
         Schild_Nvme.Read_Block (2000, Success);
         if Success then C_Putln (Msg_Rd'Address, Msg_Rd'Length); end if;
         Buf := Schild_Nvme.Get_Buffer;
         for I in 0 .. 511 loop
            Buf (I) := Interfaces.Unsigned_8 (I mod 256);
         end loop;
         Schild_Nvme.Fill_Buffer (Buf);
         Schild_Nvme.Write_Block (2000, Success);
         if Success then C_Putln (Msg_Wr'Address, Msg_Wr'Length); end if;
         Schild_Nvme.Read_Block (2000, Success);
         if Success then
            Buf := Schild_Nvme.Get_Buffer;
            if Buf (0) = 0 and Buf (255) = 255 and Buf (511) = 255 then
               C_Putln (Msg_Vf'Address, Msg_Vf'Length);
            else
               C_Putln (Msg_Err'Address, Msg_Err'Length);
            end if;
         end if;
      end;

      -- Persist the boot log captured so far (NVMe messages) to LBA 2000+.
      Schild_Net_Stack.Flush_Log_To_Nvme;
      C_Kbd_Leds (16#06#);  --  CapsLock+NumLock = NVMe write done
   end if;

   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- [SEL4 Stage 3] Try to load seL4 microkernel (toggleable via ENABLE_SEL4)
   Sel4_Result := Sel4_Launch_Init (Multiboot_Info, Get_Kernel_End);
   if Sel4_Result /= 0 then
      C_Putln (Msg_Sel4_Fail'Address, Msg_Sel4_Fail'Length);
   end if;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   --  Run the MLS server policy self-test.
   Schild_Server_Init;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== Network stack initialization (firewall + filter + limiter) ======
   Schild_Net_Init.Init_All;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== e1000e network driver initialization ======
   C_Putln (Msg_Boot'Address, Msg_Boot'Length);
   Schild_E1000e.Init;
   -- P4: Test TX — send a minimal Ethernet frame
   if Schild_E1000e.Is_Ready then
      declare
         Test_Frame : Schild_E1000e.Unsigned_8_Array (0 .. 63) :=
           (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
            16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#01#,
            16#08#, 16#00#,
            others => 16#00#);
         Msg_TX : constant String := "[E1000E] TX: broadcast sent";
         Rx_Buf : Schild_E1000e.Unsigned_8_Array (0 .. 63) := (others => 0);
         Rx_Len : Interfaces.Unsigned_16 := 0;
         Got    : Boolean := False;
         Msg_Rx : constant String := "[E1000E] RX: packet from peer!";
         Msg_No : constant String := "[E1000E] RX: no peer packet";
      begin
         -- Send broadcast frame (received by peer VM)
         Schild_E1000e.Send_Packet (Test_Frame, 64);
         C_Putln (Msg_TX'Address, Msg_TX'Length);

          -- Poll for incoming frame from peer VM with a real-time TSC timeout.
          -- A magic 200_000_000-iteration busy-poll stalled bare-metal boot for
          -- ~100 s (no peer exists). 1 s at ~2 GHz invariant TSC is ample for
          -- the self-test; raise Rx_Window_Ticks for QEMU cross-VM RX testing.
          declare
             use type Interfaces.Unsigned_64;
             Rx_Window_Ticks : constant Interfaces.Unsigned_64 := 2_000_000_000;
             Tsc_Start       : constant Interfaces.Unsigned_64 := C_Rdtsc;
          begin
             loop
                Got := Schild_E1000e.Poll_Rx (Rx_Buf, Rx_Len);
                exit when Got;
                exit when C_Rdtsc - Tsc_Start > Rx_Window_Ticks;
             end loop;
          end;
         if Got then
            C_Putln (Msg_Rx'Address, Msg_Rx'Length);
         else
            C_Putln (Msg_No'Address, Msg_No'Length);
         end if;
      end;
   end if;
   C_Putln (Msg_Boot'Address, Msg_Boot'Length);
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== IDT and interrupt initialization ======
   Schild_Interrupt_Init.Init_All;
   C_Putln (Msg_Idt'Address, Msg_Idt'Length);
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== SMP LAPIC test: read APIC ID ======
   declare
      Msg_Apic : constant String := "[SMP] LAPIC test: APIC ID = ";
      Apic_Id  : Interfaces.Unsigned_32;
   begin
      System.Machine_Code.Asm
        ("movl $0xFEE00020, %%eax;" &
         "movl (%%eax), %%eax;" &
         "shrl $24, %%eax;",
         Outputs => Interfaces.Unsigned_32'Asm_Output ("=a", Apic_Id),
         Volatile => True);
      declare
         use type Interfaces.Unsigned_32;
         Id_Char : constant Character :=
           Character'Val (48 + Integer (Apic_Id and 16#F#));
         Id_Str  : constant String (1 .. 1) := (1 => Id_Char);
      begin
         C_Puts (Msg_Apic'Address, Msg_Apic'Length);
         C_Puts (Id_Str'Address, 1);
         C_Puts (Msg_CRLF'Address, 2);
      end;
   end;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== P8: SMP — Start Application Processors ======
   Schild_Smp_Bootstrap.Init;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   Schild_Net_Stack.Flush_Log_To_Nvme;

   C_Putln (Msg_Boot'Address, Msg_Boot'Length);

   Init_Process_Table (Schild_Kernel_State.Proc_Table);

   Create_Process
     (Table => Schild_Kernel_State.Proc_Table, Parent_Pid => 0,
      Thread_Cap => 1, VSpace_Cap => 3, CNode_Cap => 2,
      Level => Public_Level, New_Pid => Root_Pid, Status => Status);
   if Status = Success then
      C_Putln (Msg_T1_OK'Address, Msg_T1_OK'Length);
   else
      C_Putln (Msg_T1_FAIL'Address, Msg_T1_FAIL'Length);
   end if;

   declare
      Child : Process_Id;
   begin
      Create_Process
        (Table => Schild_Kernel_State.Proc_Table, Parent_Pid => Root_Pid,
         Thread_Cap => 10, VSpace_Cap => 11, CNode_Cap => 12,
         Level => Public_Level, New_Pid => Child, Status => Status);
      if Status = Success then
         C_Putln (Msg_T2_OK'Address, Msg_T2_OK'Length);
      else
         C_Putln (Msg_T2_FAIL'Address, Msg_T2_FAIL'Length);
      end if;

      declare
         Bad_Pid : Process_Id; Bad_Status : Proc_Status;
      begin
         Create_Process
           (Table => Schild_Kernel_State.Proc_Table, Parent_Pid => Child,
            Thread_Cap => 20, VSpace_Cap => 21, CNode_Cap => 22,
            Level => Secret_Level, New_Pid => Bad_Pid, Status => Bad_Status);
         if Bad_Status = Mls_Violation then
            C_Putln (Msg_T3_OK'Address, Msg_T3_OK'Length);
         else
            C_Putln (Msg_T3_FAIL'Address, Msg_T3_FAIL'Length);
         end if;
      end;

      Terminate_Process (Schild_Kernel_State.Proc_Table, Child,
         Caller_Level => Public_Level, Force => False, Status => Status);
      if Status = Success then
         C_Putln (Msg_T4a_OK'Address, Msg_T4a_OK'Length);
      else
         C_Putln (Msg_T4a_FAIL'Address, Msg_T4a_FAIL'Length);
      end if;

      Wait_Process (Schild_Kernel_State.Proc_Table, Child, Status => Status);
      if Status = Success then
         C_Putln (Msg_T4b_OK'Address, Msg_T4b_OK'Length);
      else
         C_Putln (Msg_T4b_FAIL'Address, Msg_T4b_FAIL'Length);
      end if;

      -- Test5: MLS Termination Enforcement — No Control Up
      --  Set up a secret-level process and try to terminate it from a public
      --  caller, expecting an MLS violation (no control up).
      declare
         Secret_Slot : constant Integer := 3;  --  Slot of the secret process.
         T5_Status   : Proc_Status;
      begin
         --  Populate the secret process slot.
         Schild_Kernel_State.Proc_Table (Secret_Slot).Pid        := 3;
         Schild_Kernel_State.Proc_Table (Secret_Slot).Parent_Pid := Root_Pid;
         Schild_Kernel_State.Proc_Table (Secret_Slot).Level      := Secret_Level;
         Schild_Kernel_State.Proc_Table (Secret_Slot).State      := Ready;
         Schild_Kernel_State.Proc_Table (Secret_Slot).Thread_Cap := 99;
         Schild_Kernel_State.Proc_Table (Secret_Slot).VSpace_Cap := 99;
         Schild_Kernel_State.Proc_Table (Secret_Slot).CNode_Cap  := 99;

         --  Attempt termination from a public caller (should be denied).
         Terminate_Process (Schild_Kernel_State.Proc_Table, 3,
            Caller_Level => Public_Level, Force => False, Status => T5_Status);
         if T5_Status = Mls_Violation then
            C_Putln (Msg_T5_OK'Address, Msg_T5_OK'Length);
         else
            C_Putln (Msg_T5_FAIL'Address, Msg_T5_FAIL'Length);
         end if;
      end;
   end;
   declare
      M : constant String := "[STAGE] MLS audit done";
   begin
      C_Putln (M'Address, M'Length);
   end;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ================================================================
   --  KERNEL LOGIC: scheduler start and main loop (hlt)
   -- ================================================================
      -- ====== SchildFS write test (Stage 7.8) ======
   if Schild_Nvme.Is_Ready then
      declare
         use Interfaces;
         FS_OK   : Boolean;
         F       : Schild_Schild_Fs.File_Info;
         OK      : Boolean;
         Buf     : Schild_Schild_Fs.Unsigned_8_Array (0 .. 31);
         Len     : Unsigned_32;
         Msg_FS1 : constant String := "[NVFS] Init OK";
         Msg_FS2 : constant String := "[NVFS] Create test.txt OK";
         Msg_FS3 : constant String := "[NVFS] Write OK";
         Msg_FS4 : constant String := "[NVFS] Read-back VERIFY OK";
      begin
         Schild_Schild_Fs.Init (FS_OK);
         if FS_OK then
            C_Putln (Msg_FS1'Address, Msg_FS1'Length);
            Schild_Schild_Fs.Create_File ("test.txt", 512, OK);
            if OK then
               C_Putln (Msg_FS2'Address, Msg_FS2'Length);
               Schild_Schild_Fs.Open ("test.txt", F, OK);
               if OK then
               declare
                  Data : constant Schild_Schild_Fs.Unsigned_8_Array (0 .. 511) :=
                    (0=>78,1=>101,2=>118,3=>97,4=>79,5=>83,
                     6=>32,7=>119,8=>114,9=>105,10=>116,11=>101,
                     12=>115,13=>116,14=>33,15=>10,
                     others=> 0);
               begin
                  Schild_Schild_Fs.Write_File (F, Data, OK);
                  if OK then
                     C_Putln (Msg_FS3'Address, Msg_FS3'Length);
                     F.Curr_Off := 0;
                     Schild_Schild_Fs.Read (F, Buf, Len, OK);
                     if OK and then Len >= 3 and then
                        Buf(0)=78 and then Buf(1)=101 then
                        C_Putln (Msg_FS4'Address, Msg_FS4'Length);
                     end if;
                  end if;
               end;
             end if;
            end if;
         end if;
      end;
   end if;
   declare
      M : constant String := "[STAGE] SchildFS test done";
   begin
      C_Putln (M'Address, M'Length);
   end;
   Schild_Net_Stack.Flush_Log_To_Nvme;

   -- ====== Process Manager demo (Stage 7.8) ======
   declare
      use Interfaces;
      P_Table  : Schild_Process_Manager.Process_Table;
      P1, P2   : Schild_Process_Manager.Process_Id;
      St       : Schild_Process_Manager.Proc_Status;
      Msg_P1   : constant String := "[PROC] Process 1 running (round ";
      Msg_P2   : constant String := "[PROC] Process 2 running (round ";
      Counter1 : Unsigned_32 := 0;
      Counter2 : Unsigned_32 := 0;
      Tick     : Unsigned_32 := 0;
   begin
      Schild_Process_Manager.Init_Process_Table (P_Table);

      -- Create two processes with dummy caps (kernel-mode demo)
      Schild_Process_Manager.Create_Process (P_Table, 1, 100, 200, 300,
         Schild_Process_Manager.Confidential_Level, P1, St);
      Schild_Process_Manager.Create_Process (P_Table, 1, 101, 201, 301,
         Schild_Process_Manager.Confidential_Level, P2, St);

      -- Cooperative round-robin: 5 rounds x 2 processes
      for Round in 1 .. 5 loop
         -- Process 1 work
         Counter1 := Counter1 + 1;
         for J in 1 .. 5000 loop
            Counter1 := (Counter1 * 1103515245) + 12345;
         end loop;
         Tick := Tick + 1;

         -- Process 2 work
         Counter2 := Counter2 + 1;
         for J in 1 .. 5000 loop
            Counter2 := (Counter2 * 1103515245) + 12345;
         end loop;
         Tick := Tick + 1;
      end loop;
   end;

   -- ====== Stage 7.9: TCP/IP Network Stack + HTTP Server ======
   if Schild_E1000e.Is_Ready then
      Schild_Net_Stack.Init;
      Schild_Net_Stack.Flush_Log_To_Nvme;
      -- Enable the e1000e IRQ path (bare-metal only): LAPIC + IDT vector 0x30
      -- + sti, so Run_Loop halts on the RX interrupt instead of busy-polling.
      C_Apic_Init;
      C_Idt_Raw;
      -- Clear any pre-boot interrupt cause (the P4 TX self-test raised TXDW,
      -- whose MSI was lost while the LAPIC was disabled).  If the ICR stays
      -- set, the device never sends a fresh MSI for the first RX interrupt,
      -- so the CPU never wakes from hlt.
      Schild_E1000e.Clear_IRQ;
      C_Sti;
      C_Putln (Msg_Irq_On'Address, Msg_Irq_On'Length);
      Schild_Net_Stack.Flush_Log_To_Nvme;  -- persist IRQ-ready marker
      Schild_Net_Stack.Run_Loop;
   else
      Schild_Kernel_Logic.Init;
      Schild_Net_Stack.Flush_Log_To_Nvme;
      Schild_Kernel_Logic.Run;
   end if;

end Schild_Kernel_Entry;
