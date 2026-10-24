-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_Launch_Model with SPARK_Mode => On is

   procedure Bind_Timeout_EP (S : in out Launch_State; Slot : Natural) is
   begin
      S.Timeout_EP := Slot;
   end Bind_Timeout_EP;

   procedure Launch
     (S          : in out Launch_State;
      D          : Domain;
      Fault_Slot : Natural)
   is
   begin
      case D is
         when NetServer =>
            S.Net_Launched := True;
            S.Net_Fault_EP := Fault_Slot;
         when MLS =>
            S.MLS_Launched := True;
            S.MLS_Fault_EP := Fault_Slot;
         when Config_Daemon =>
            S.Cfg_Launched := True;
            S.Cfg_Fault_EP := Fault_Slot;
      end case;
      S.Launched_Count := S.Launched_Count + 1;
   end Launch;

end Schild_Launch_Model;
