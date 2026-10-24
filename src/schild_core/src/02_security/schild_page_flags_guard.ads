pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Page_Flags_Guard is

   --  Memory segment classes checked by the page-flag guard.
   type Segment_Class_Type is (Segment_Kernel_Code, Segment_Kernel_Data, Segment_User_Code, Segment_User_Data);

   --  Alias for the segment class.
   subtype Memory_Segment_Kind is Segment_Class_Type;

   procedure Check_Page_Flags
     (Flags      : in     Unsigned_64;
      Seg_Class  : in     Segment_Class_Type;
      Is_Trusted :    out Boolean)
   with
     Global => null;

end Schild_Page_Flags_Guard;
