--  Schild TCB - per-packet firewall (rate limiting, encryption, port blocking).
--  Public scaffold of the network ingress path; the full packet-filter logic is
--  not yet implemented.

with Interfaces;
with Schild_Net_Filter;
with Schild_Net_Limiter;
with Schild_Net_Parser;
with Schild_Net_Crypto;
with Schild_Icmp_Handler;
with Schild_Udp_Handler;
with Schild_Socket_Manager;

package Schild_Firewall with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   use Schild_Net_Filter;
   use Schild_Net_Limiter;
   use Schild_Socket_Manager;

   --  Outcome of processing one packet through the firewall.
   type Firewall_Verdict is (Allowed, Dropped, Rate_Limited, Encrypted, Logged);

   --  Firewall session state: limiter plus aggregate counters.
   type Firewall_Context is record
      Limiter        : Limiter_Passport_Record;
      Total_Allowed  : Natural := 0;
      Total_Dropped  : Natural := 0;
      Session_Active : Boolean := False;
   end record;

   ------------------------------------------------------------
   --  Firewall operations.
   ------------------------------------------------------------

   --  Initialise the firewall context and arm the session.
   procedure Init_Firewall (Context : out Firewall_Context);

   --  Inspect one packet and return a firewall verdict.
   procedure Process_Incoming_Packet
     (Context : in out Firewall_Context;
      Packet  : in     Network_Packet_Record;
      Verdict :    out Firewall_Verdict);

   --  Consume one limiter token; Allowed reports whether it passed.
   procedure Apply_Rate_Limit
     (Context : in out Firewall_Context;
      Allowed :    out Boolean);

   --  Encrypt an outgoing packet (scaffold).
   procedure Encrypt_Outgoing_Packet
     (Context : in out Firewall_Context;
      Success :    out Boolean);

   --  Block a given port for a process (scaffold trace).
   procedure Block_Port
     (Context : in out Firewall_Context;
      Port    :        Application_Port_Type;
      Pid     :        Interfaces.Unsigned_32);
end Schild_Firewall;