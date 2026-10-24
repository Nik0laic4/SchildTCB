pragma Spark_Mode (On);
pragma Unevaluated_Use_Of_Old (Allow); --  Permit 'Old in postconditions.

with Interfaces;
use Interfaces;

package Schild_Nvram_Manager is

   type Block_Id_Range is range 0 .. 255;

   type Nvram_Block_Record is record
      Checksum  : Unsigned_64;
      Is_Locked : Boolean;
   end record;

   type Nvram_Storage_Matrix is array (Block_Id_Range) of Nvram_Block_Record;

   procedure Sync_Nvram_Block
     (Block_ID : in     Block_Id_Range;
      Storage  : in out Nvram_Storage_Matrix;
      Success  :    out Boolean)
   with
     Global => null,
     Post   => (if not Success then Storage (Block_ID).Checksum = Storage (Block_ID).Checksum'Old);

end Schild_Nvram_Manager;
