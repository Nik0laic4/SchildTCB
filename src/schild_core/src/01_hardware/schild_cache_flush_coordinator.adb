with System.Machine_Code; use System.Machine_Code;

package body Schild_Cache_Flush_Coordinator with
  SPARK_Mode => Off --  CLFLUSH coordination scaffold.
is

   procedure Invalidate_Cache_Line
     (Line_Addr : in     Target_Line_Address;
      Success   :    out Boolean)
   is
   begin
      --  Flush one cache line.
      System.Machine_Code.Asm (Template => "clflush (%0)", Inputs => Target_Line_Address'Asm_Input ("r", Line_Addr), Volatile => True);
      System.Machine_Code.Asm (Template => "mfence", Volatile => True);
      Success := True;
   end Invalidate_Cache_Line;

end Schild_Cache_Flush_Coordinator;
