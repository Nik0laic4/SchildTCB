-- Schild TCB Server Security Policy — formal MLS Bell-LaPadula model.
-- Complete system service isolation + cryptographic IPC verification.
-- Each system service — in its own security ring (5 levels).
-- Compliance: Bell-LaPadula model (SPARK_Mode => On; not part of the verify.gpr proof set).

with Schild_Cap_Space;
with Interfaces;

package Schild_Server_Security_Policy with
  SPARK_Mode => On
is
   pragma Elaborate_Body;
   use Schild_Cap_Space;
   use Interfaces;

   -- ============================================================
   --  MLS security levels, lowest to highest.
   -- ============================================================
   type Security_Level is
     (Level_Public,      --  Least privileged (public data).
      Level_Internal,     --  Internal, non-public.
      Level_Confidential, --  Confidential data.
      Level_Secret,       --  Secret data.
      Level_Top_Secret);  --  Most privileged (key material).

   --  A higher level dominates a lower one; this ordering drives the
   --  Bell-LaPadula "no read up / no write down" rules below.

   -- ============================================================
   --  System services, each bound to one security ring.
   -- ============================================================
   type Server_Role is
     (Role_Root_Task,       -- PID 1 — Level_Top_Secret
      Role_Init_Manager,    -- analog of systemd — Level_Secret
      Role_Crypto_Engine,   --  In-kernel crypto (AES/SHA).
      Role_KDF_Service,     -- Key Derivation Function — Level_Secret
      Role_Audit_Logger,    --  Append-only audit sink.
      Role_Net_Firewall,    --  Per-packet firewall.
      Role_Net_Filter,      --  Stateful L3/L4 filter.
      Role_TLS_Terminator,  --  TLS termination.
      Role_HTTP_Gateway,    --  HTTP reverse proxy.
      Role_Media_Server,    --  Media streaming.
      Role_Static_Server,   --  Static file serving.
      Role_User_Worker,     --  User-space worker.
      Role_DB_Proxy,        --  Database proxy.
      Role_DB_Engine);      --  Database engine.

   --  Maps each server role to its MLS clearance level.
   type Role_Level_Map is array (Server_Role) of Security_Level;

   Default_Policy : constant Role_Level_Map :=
     (Role_Root_Task       => Level_Top_Secret,
      Role_Init_Manager    => Level_Secret,
      Role_Crypto_Engine   => Level_Secret,
      Role_KDF_Service     => Level_Secret,
      Role_Audit_Logger    => Level_Top_Secret,
      Role_Net_Firewall    => Level_Confidential,
      Role_Net_Filter      => Level_Confidential,
      Role_TLS_Terminator  => Level_Confidential,
      Role_HTTP_Gateway    => Level_Internal,
      Role_Media_Server    => Level_Internal,
      Role_Static_Server   => Level_Public,
      Role_User_Worker     => Level_Internal,
      Role_DB_Proxy        => Level_Confidential,
      Role_DB_Engine       => Level_Secret);

   -- ============================================================
   --  Bell-LaPadula access rules.
   -- ============================================================

   --  Two roles may communicate only at the same level.
   function Can_Communicate
     (Source_Role, Target_Role : Server_Role) return Boolean
   with Post => Can_Communicate'Result =
     (Default_Policy (Source_Role) = Default_Policy (Target_Role));
     --  Same-level communication only.

   --  Read allowed when the reader dominates the owner (no read up).
   function Can_Read
     (Reader_Role, Owner_Role : Server_Role) return Boolean
   with Post => Can_Read'Result =
     (Default_Policy (Reader_Role) >= Default_Policy (Owner_Role));
     --  Reader must dominate the owner.

   --  Write allowed when the writer is dominated by the target (no write down).
   function Can_Write
     (Writer_Role, Target_Role : Server_Role) return Boolean
   with Post => Can_Write'Result =
     (Default_Policy (Writer_Role) <= Default_Policy (Target_Role));
     --  Writer must be dominated by the target.

   --  The clearance level assigned to a role.
   function Min_Level_For_Role (Role : Server_Role) return Security_Level
   is (Default_Policy (Role));

end Schild_Server_Security_Policy;
