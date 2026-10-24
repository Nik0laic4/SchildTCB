with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;

package Schild_Smp_Tlb with
  SPARK_Mode => On
is

   type Virtual_Page_Address is new Interfaces.Unsigned_64;
   type Tlb_Status_Type is (Tlb_Idle, Tlb_Pending, Tlb_Invalidated);

   type Tlb_Message_Record is record
      Target_Core    : Schild_Smp_Spinlock.Core_Id_Type := 0;
      Page_To_Flush  : Virtual_Page_Address := 0;
      Status         : Tlb_Status_Type := Tlb_Idle;
   end record;

   procedure Broadcast_Tlb_Shootdown
     (Message : in out Tlb_Message_Record;
      Success :    out Boolean)
   with Pre => Message.Page_To_Flush /= 0,
        Post => (if Success then Message.Status = Tlb_Invalidated);

end Schild_Smp_Tlb;
