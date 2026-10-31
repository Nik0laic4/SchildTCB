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

   --  Fixed-size port blocklist.
   Max_Blocked_Ports : constant := 16;
   type Port_Table is array (1 .. Max_Blocked_Ports) of Application_Port_Type;

   --  Firewall session state: limiter, counters, and the port blocklist.
   type Firewall_Context is record
      Limiter        : Limiter_Passport_Record;
      Total_Allowed  : Natural := 0;
      Total_Dropped  : Natural := 0;
      Session_Active : Boolean := False;
      Blocked_Ports  : Port_Table := (others => 1);
      Num_Blocked    : Natural range 0 .. Max_Blocked_Ports := 0;
   end record;

   ------------------------------------------------------------
   --  Firewall operations.
   ------------------------------------------------------------

   --  Initialise the firewall context and arm the session.
   procedure Init_Firewall (Context : out Firewall_Context) with
     Post => Context.Session_Active
             and Context.Total_Allowed = 0
             and Context.Total_Dropped = 0
             and Context.Num_Blocked = 0;

   --  Inspect one packet and return a firewall verdict. The aggregate counters
   --  only grow.
   procedure Process_Incoming_Packet
     (Context : in out Firewall_Context;
      Packet  : in     Network_Packet_Record;
      Verdict :    out Firewall_Verdict) with
     Post => Context.Total_Allowed >= Context.Total_Allowed'Old
             and Context.Total_Dropped >= Context.Total_Dropped'Old;

   --  Consume one limiter token; Allowed reports whether it passed.
   procedure Apply_Rate_Limit
     (Context : in out Firewall_Context;
      Allowed :    out Boolean) with
     Post => (if Allowed then Context.Limiter.Rate_Limit_Ok)
             and Context.Total_Allowed = Context.Total_Allowed'Old
             and Context.Total_Dropped = Context.Total_Dropped'Old
             and Context.Num_Blocked = Context.Num_Blocked'Old;

   --  Encrypt an outgoing packet (scaffold).
   procedure Encrypt_Outgoing_Packet
     (Context : in out Firewall_Context;
      Success :    out Boolean) with
     Post => Success;

   --  Block a given port (adds it to the blocklist; no-op if full or present).
   procedure Block_Port
     (Context : in out Firewall_Context;
      Port    :        Application_Port_Type;
      Pid     :        Interfaces.Unsigned_32) with
     Post => Context.Num_Blocked <= Max_Blocked_Ports;

   --  True when the port is in the blocklist.
   function Is_Port_Blocked
     (Context : Firewall_Context;
      Port    : Application_Port_Type) return Boolean;
end Schild_Firewall;