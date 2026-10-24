-- Schild TCB — network identity (single source of truth for the local IPv4
-- address). The default is 192.168.3.200; override at build time by setting
-- SCHILD_IP (dotted quad): build.sh generates an override spec into build/gen/
-- and places it first on the Ada include path.
with Interfaces; use Interfaces;

package Schild_Net_Config is
   pragma Elaborate_Body;
   Our_IP : constant Unsigned_32 := 16#C0A8_03C8#;  -- 192.168.3.200
end Schild_Net_Config;
