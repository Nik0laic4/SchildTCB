-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package Schild_Boot_State with
  SPARK_Mode => On
is

   type Boot_Phase is (
      Uninitialized,
      Multiboot_Validated,
      Memory_Ready,
      Kernel_Ready,
      Faulted);

   function Can_Advance (Current, Next : Boot_Phase) return Boolean;

   procedure Advance
     (Current : in out Boot_Phase;
      Next    : Boot_Phase;
      Message : String);

   function Phase_Image (Phase : Boot_Phase) return String;

end Schild_Boot_State;
