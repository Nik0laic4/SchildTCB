package Schild_Boot_Parser with
  SPARK_Mode => On
is

   --  A fixed-length kernel command line (64 characters).
   subtype Cmd_Line_Index is Positive range 1 .. 64;
   type Boot_Cmd_Line_Type is array (Cmd_Line_Index) of Character;

   --  Parsed boot configuration flags.
   type Boot_Config_Type is record
      Audit_Enabled  : Boolean;
      Enclaves_Strict: Boolean;
      Is_Parsed      : Boolean;
   end record;

   --  Parse the command line into the configuration record.
   procedure Parse_Boot_Arguments
     (Cmd_Line : in Boot_Cmd_Line_Type;
      Config   : out Boot_Config_Type)
   with
     Post => (if Config.Is_Parsed then 
                (if Config.Audit_Enabled then Cmd_Line (1) = 'a'));

end Schild_Boot_Parser;
