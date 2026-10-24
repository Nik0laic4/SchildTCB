package body Schild_Boot_Parser with
  SPARK_Mode => On
is

   --------------------------
   -- Parse_Boot_Arguments --
   --------------------------
   procedure Parse_Boot_Arguments
     (Cmd_Line : in Boot_Cmd_Line_Type;
      Config   : out Boot_Config_Type)
   is
   begin
      --  Start from a safe default configuration.
      Config := (Audit_Enabled => False, Enclaves_Strict => False, Is_Parsed => False);

      --  Flag 'a' enables the audit log.
      if Cmd_Line (1) = 'a' then
         Config.Audit_Enabled := True;
         
         if Cmd_Line (2) = 's' then
            Config.Enclaves_Strict := True;
         end if;
         
         Config.Is_Parsed := True;
      else
         --  Unknown flag: reject the directive (fail closed — do not accept an
         --  unrecognized boot option as if it had been parsed).
         Config.Is_Parsed := False;
      end if;
   end Parse_Boot_Arguments;

end Schild_Boot_Parser;
