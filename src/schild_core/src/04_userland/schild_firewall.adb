--  Schild TCB - network firewall body (token-bucket rate limiter + verdicts).
--  Public scaffold: emits decisions over the UART; packet-filter and crypto
--  verdicts are not yet implemented (no private counterpart).

with Schild_Log;
with Schild_Text;

package body Schild_Firewall with
  SPARK_Mode => On
is
   use type Interfaces.Unsigned_32;

   ---------------
   -- Init_Firewall --
   ---------------
   procedure Init_Firewall (Context : out Firewall_Context) is
   begin
      Context := Firewall_Context'(others => <>);
      Context.Limiter.Tokens := 1000;
      Context.Session_Active := True;
      Schild_Log.Put_Line ("[FW] Firewall initialized (Token Bucket: 1000 tokens)");
   end Init_Firewall;

   ------------------------------
   -- Process_Incoming_Packet  --
   ------------------------------
   procedure Process_Incoming_Packet
     (Context : in out Firewall_Context;
      Packet  : in     Network_Packet_Record;
      Verdict :    out Firewall_Verdict)
   is
      Rate_Ok : Boolean;
   begin
      --  Drop packets with an invalid (zero) source or destination address.
      if Packet.Source_IP = 0 or else Packet.Dest_IP = 0 then
         Verdict := Dropped;
         if Context.Total_Dropped < Natural'Last then
            Context.Total_Dropped := Context.Total_Dropped + 1;
         end if;
         Schild_Log.Put_Line ("[FW] Packet DROPPED (invalid IP)");
         return;
      end if;

      --  Apply the token-bucket limiter (DDoS protection).
      Apply_Rate_Limit (Context, Rate_Ok);
      if not Rate_Ok then
         Verdict := Rate_Limited;
         Schild_Log.Put_Line ("[FW] Packet RATE_LIMITED (DDoS protection)");
         return;
      end if;

      --  The packet passed both checks: allow it.
      Verdict := Allowed;
      if Context.Total_Allowed < Natural'Last then
         Context.Total_Allowed := Context.Total_Allowed + 1;
      end if;
      Schild_Log.Put_Line ("[FW] Packet ALLOWED");
   end Process_Incoming_Packet;

   --------------------------
   -- Apply_Rate_Limit     --
   --------------------------
   procedure Apply_Rate_Limit
     (Context : in out Firewall_Context;
      Allowed :    out Boolean)
   is
      Tokens_Needed : constant Token_Count_Type := 1;
   begin
      Consume_Traffic_Token (Context.Limiter, Tokens_Needed, Allowed);
   end Apply_Rate_Limit;

   --------------------------------
   -- Encrypt_Outgoing_Packet   --
   --------------------------------
   procedure Encrypt_Outgoing_Packet
     (Context : in out Firewall_Context;
      Success :    out Boolean)
   is
   begin
      --  Scaffold: report success without transforming the packet.
      Success := True;
      Schild_Log.Put_Line ("[FW] Packet encrypted (stub)");
   end Encrypt_Outgoing_Packet;

   -----------------
   -- Block_Port  --
   -----------------
   procedure Block_Port
     (Context : in out Firewall_Context;
      Port    :        Application_Port_Type;
      Pid     :        Interfaces.Unsigned_32)
   is
   begin
      Schild_Log.Put_String ("[FW] Port blocked: ");
      --  Render the blocked port number as decimal for the UART trace.
      declare
         Buf : Schild_Text.Image_String;
         Len : Natural;
      begin
         Schild_Text.Image (Natural (Port), Buf, Len);
         Schild_Log.Put_String (Buf (1 .. Len));
      end;
      Schild_Log.Put_Line (" for PID (stub)");
   end Block_Port;

end Schild_Firewall;