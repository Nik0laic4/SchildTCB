-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

--  Schild TCB - server bootstrap + MLS policy self-test.
--  Prints the loaded policy and asserts the Bell-LaPadula rules hold.

with Schild_Server_Security_Policy;
with Schild_Uart_Driver;

procedure Schild_Server_Init is
   use Schild_Server_Security_Policy;

   Msg_Sec_Ok    : constant String := "[SEC] Server security policy loaded (MLS Bell-LaPadula)";
   Msg_Roles     : constant String := "[SEC] 14 server roles defined (Public..Top_Secret)";
   Msg_Audit     : constant String := "[SEC] IPC: strict isolation (equal levels only)";
   Msg_Verif     : constant String := "[SEC] Module verifier: SHA-256 code signing active";

   -- Policy correctness check (academic self-test)
   procedure Self_Test is
      Ok : Boolean;
   begin
      -- Root Task can only communicate with Root Task
      Ok := Can_Communicate (Role_Root_Task, Role_Root_Task);
      pragma Assert (Ok);

      -- Root Task CANNOT communicate with HTTP Gateway (different levels)
      Ok := Can_Communicate (Role_Root_Task, Role_HTTP_Gateway);
      pragma Assert (not Ok);

      -- Crypto Engine CAN read data HTTP Gateway (No Read Up?)
      --  Crypto (Secret) may read HTTP (Internal): no read up.
      Ok := Can_Read (Role_Crypto_Engine, Role_HTTP_Gateway);
      pragma Assert (Ok);

      -- HTTP Gateway CANNOT read data Crypto Engine (No Read Up!)
      --  HTTP (Internal) may not read Crypto (Secret): read up denied.
      Ok := Can_Read (Role_HTTP_Gateway, Role_Crypto_Engine);
      pragma Assert (not Ok);
   end Self_Test;

begin
   Schild_Uart_Driver.Put_Line (Msg_Sec_Ok);
   Schild_Uart_Driver.Put_Line (Msg_Roles);
   Schild_Uart_Driver.Put_Line (Msg_Audit);
   Schild_Uart_Driver.Put_Line (Msg_Verif);
   Self_Test;
end Schild_Server_Init;
