-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_Boot_State with
  SPARK_Mode => On
is

   function Can_Advance (Current, Next : Boot_Phase) return Boolean is
   begin
      case Current is
         when Uninitialized =>
            return Next = Multiboot_Validated;
         when Multiboot_Validated =>
            return Next = Memory_Ready or else Next = Faulted;
         when Memory_Ready =>
            return Next = Kernel_Ready or else Next = Faulted;
         when Kernel_Ready =>
            return False;
         when Faulted =>
            return False;
      end case;
   end Can_Advance;

   procedure Advance
     (Current : in out Boot_Phase;
      Next    : Boot_Phase;
      Message : String)
   is
   begin
      if Can_Advance (Current, Next) then
         Current := Next;
      else
         Current := Faulted;
      end if;
   end Advance;

   function Phase_Image (Phase : Boot_Phase) return String is
   begin
      case Phase is
         when Uninitialized =>
            return "UNINITIALIZED";
         when Multiboot_Validated =>
            return "MULTIBOOT_VALIDATED";
         when Memory_Ready =>
            return "MEMORY_READY";
         when Kernel_Ready =>
            return "KERNEL_READY";
         when Faulted =>
            return "FAULTED";
      end case;
   end Phase_Image;

end Schild_Boot_State;
