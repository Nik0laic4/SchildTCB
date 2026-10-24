-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Schild_Log;
with Schild_Text;

package body Schild_Boot_Runtime with
  SPARK_Mode => On
is

   Runtime_Status : Boot_Status := Booting;
   Recovery_Attempts : Natural := 0;

   function Current_Status return Boot_Status is
   begin
      return Runtime_Status;
   end Current_Status;

   procedure Mark_Stable is
   begin
      Runtime_Status := Stable;
   end Mark_Stable;

   procedure Mark_Faulted is
   begin
      Runtime_Status := Faulted;
   end Mark_Faulted;

   procedure Report_Failure (Message : String) is
   begin
      Schild_Log.Put_String ("Schild TCB[FAULTED] ");
      Schild_Log.Put_Line (Message);
      Mark_Faulted;
   end Report_Failure;

   procedure Enter_Recovery_Mode (Message : String) is
   begin
      if Recovery_Attempts < Natural'Last then
         Recovery_Attempts := Recovery_Attempts + 1;
      end if;
      Schild_Log.Put_String ("Schild TCB[RECOVERY] ");
      Schild_Log.Put_String (Message);
      Schild_Log.Put_String (" (attempt ");
      declare
         Buf : Schild_Text.Image_String;
         Len : Natural;
      begin
         Schild_Text.Image (Recovery_Attempts, Buf, Len);
         Schild_Log.Put_String (Buf (1 .. Len));
      end;
      Schild_Log.Put_Line (")");
      Runtime_Status := Recovering;
   end Enter_Recovery_Mode;

   function Recovery_Attempt_Count return Natural is
   begin
      return Recovery_Attempts;
   end Recovery_Attempt_Count;

   procedure Mark_Recovery_Complete is
   begin
      Runtime_Status := Recovery_Complete;
      Schild_Log.Put_String ("Schild TCB[RECOVERY_COMPLETE] recovery completed after ");
      declare
         Buf : Schild_Text.Image_String;
         Len : Natural;
      begin
         Schild_Text.Image (Recovery_Attempts, Buf, Len);
         Schild_Log.Put_String (Buf (1 .. Len));
      end;
      Schild_Log.Put_Line (" attempt(s)");
   end Mark_Recovery_Complete;

end Schild_Boot_Runtime;
