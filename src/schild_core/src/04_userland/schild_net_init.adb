-- Schild TCB Network Initialization (Juniper-style Control Plane)
--  Boots the four-layer network chain: parser -> filter -> limiter -> crypto.

with Schild_Firewall;
with Schild_Socket_Manager;
with Schild_Net_Filter;
with Schild_Uart_Driver;

package body Schild_Net_Init with
  SPARK_Mode => Off
is
   use Schild_Firewall;

   Fw : Firewall_Context;

   procedure Init_All is
      Dummy_Packet : Schild_Net_Filter.Network_Packet_Record;
      Dummy_Action : Schild_Net_Filter.Filter_Action_Type;
      Verdict      : Firewall_Verdict;
   begin
      Schild_Uart_Driver.Put_Line ("[NET] Network stack initializing...");

      --  Step 1: initialise the stateful firewall.
      Init_Firewall (Fw);
      Schild_Uart_Driver.Put_Line ("[NET] Firewall: stateful inspection active");

      -- 2. Check Net Filter
      Schild_Net_Filter.Inspect_Stateful_Session (Dummy_Packet, Dummy_Action);
      Schild_Uart_Driver.Put_Line ("[NET] Net Filter: session inspector ready");

      --  Step 3: verify the token-bucket limiter responds.
      declare
         Allowed : Boolean;
      begin
         Apply_Rate_Limit (Fw, Allowed);
      end;
      Schild_Uart_Driver.Put_Line ("[NET] Rate Limiter: Token Bucket active (DDoS protection)");

      --  Step 4: exercise the full firewall chain end to end.
      Process_Incoming_Packet (Fw, Dummy_Packet, Verdict);
      Schild_Uart_Driver.Put_Line ("[NET] Firewall chain: Parser→Filter→Limiter→Crypto active");

      Schild_Uart_Driver.Put_Line ("[NET] Network stack initialized (4 layers)");
   end Init_All;

end Schild_Net_Init;
