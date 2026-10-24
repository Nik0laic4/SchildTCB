with Schild_Timer;
package Schild_Kernel_Logic with SPARK_Mode => Off is
   procedure Init;
   procedure Tick;
   procedure Run;
   function Get_Ticks return Schild_Timer.Tick_Count_Type;
   function Is_Active return Boolean;
end Schild_Kernel_Logic;
