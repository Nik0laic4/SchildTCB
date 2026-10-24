-- Schild TCB e1000e Driver (Intel 82574L / I219-V)
package Schild_E1000e_Driver with
  SPARK_Mode => Off
is
   procedure Init;
   function Is_Ready return Boolean;
end Schild_E1000e_Driver;
