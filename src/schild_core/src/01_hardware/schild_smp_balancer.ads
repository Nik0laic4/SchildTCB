with Interfaces; use Interfaces;
with Schild_Smp_Spinlock; use Schild_Smp_Spinlock;

package Schild_Smp_Balancer with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   subtype Core_Index_Type is Schild_Smp_Spinlock.Core_Id_Type range 0 .. 63; --  Up to 64 cores.
   type Task_Count_Type is new Interfaces.Unsigned_32;

   type Core_Load_Record is record
      Core_Id    : Core_Index_Type := 0;
      Task_Count : Task_Count_Type := 0;
      Is_Active  : Boolean := False;
   end record;

   procedure Balance_Cluster_Load
     (Source_Core : in     Core_Index_Type;
      Target_Core : in     Core_Index_Type;
      Success     :    out Boolean)
   with Pre => Source_Core /= Target_Core; --  Migration must move between distinct cores.

end Schild_Smp_Balancer;
