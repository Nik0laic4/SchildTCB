-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_HM_Model with SPARK_Mode => On is

   procedure Launch (State : in out HM_State; Domain : HM_Domain) is
   begin
      case Domain is
         when HM_NetServer     => State.Net_Launched := True;
         when HM_MLS           => State.MLS_Launched := True;
         when HM_Config_Daemon => State.Cfg_Launched := True;
      end case;
   end Launch;

   procedure Evaluate
     (State  : in out HM_State;
      Domain : HM_Domain;
      Action : out HM_Action)
   is
   begin
      case Domain is
         when HM_NetServer =>
            State.Counts.Net := State.Counts.Net + 1;
            State.Net_Stopped := State.Net_Stopped
              or else State.Counts.Net > Max_Restarts;
         when HM_MLS =>
            State.Counts.MLS := State.Counts.MLS + 1;
            State.MLS_Stopped := State.MLS_Stopped
              or else State.Counts.MLS > Max_Restarts;
         when HM_Config_Daemon =>
            State.Counts.Cfg := State.Counts.Cfg + 1;
            State.Cfg_Stopped := State.Cfg_Stopped
              or else State.Counts.Cfg > Max_Restarts;
      end case;

      if All_Stopped (State) then
         Action := Module_Idle;
      elsif Count (State, Domain) > Max_Restarts then
         Action := Stop;
      else
         Action := Restart;
      end if;
   end Evaluate;

end Schild_HM_Model;
