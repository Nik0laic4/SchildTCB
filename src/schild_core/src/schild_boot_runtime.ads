-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package Schild_Boot_Runtime with
  SPARK_Mode => On
is

   type Boot_Status is (Booting, Stable, Faulted, Recovering, Recovery_Complete);

   function Current_Status return Boot_Status;

   procedure Mark_Stable;

   procedure Mark_Faulted;

   procedure Report_Failure (Message : String);

   procedure Enter_Recovery_Mode (Message : String);

   function Recovery_Attempt_Count return Natural;

   procedure Mark_Recovery_Complete;

end Schild_Boot_Runtime;
