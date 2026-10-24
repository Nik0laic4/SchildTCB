pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Tme_Manager is

   type Domain_Key_Id is range 0 .. 31;

   procedure Activate_Tme_Domain
     (Key_ID    : in     Domain_Key_Id;
      Page_Addr : in     Unsigned_64;
      Success   :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Page_Addr /= 0);

end Schild_Tme_Manager;
