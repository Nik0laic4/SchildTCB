-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package Schild_Boot_Runtime with
  SPARK_Mode => On,
  Abstract_State => (Status_State, Attempts_State)
is

   type Boot_Status is (Booting, Stable, Faulted, Recovering, Recovery_Complete);

   function Current_Status return Boot_Status with
     Global => (Input => Status_State);

   procedure Mark_Stable with
     Global => (Output => Status_State);

   procedure Mark_Faulted with
     Global => (Output => Status_State);

   procedure Report_Failure (Message : String) with
     Global => (Output => Status_State);

   procedure Enter_Recovery_Mode (Message : String) with
     Global => (In_Out => (Status_State, Attempts_State));

   function Recovery_Attempt_Count return Natural with
     Global => (Input => Attempts_State);

   procedure Mark_Recovery_Complete with
     Global => (Input => Attempts_State, Output => Status_State);

end Schild_Boot_Runtime;
