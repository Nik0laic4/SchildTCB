with Interfaces; use Interfaces;

package Schild_Timer with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Tick_Count_Type is new Interfaces.Unsigned_64;
   
   type Timer_Hardware_Record is record
      System_Ticks : Tick_Count_Type := 0;
      Is_Running   : Boolean := False;
   end record;

   procedure Update_System_Tick
     (Timer : in out Timer_Hardware_Record)
   with Post => Timer.System_Ticks = Timer.System_Ticks'Old + 1;
   --  Each tick advances the system tick counter by one.

end Schild_Timer;
