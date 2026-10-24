pragma Spark_Mode (On);

package body Schild_Nvram_Manager is

   procedure Sync_Nvram_Block
     (Block_ID : in     Block_Id_Range;
      Storage  : in out Nvram_Storage_Matrix;
      Success  :    out Boolean)
   is
   begin
      if not Storage (Block_ID).Is_Locked then
         Storage (Block_ID).Checksum := Storage (Block_ID).Checksum + 16#1234#;
         Success                     := True;
      else
         Success                     := False;
      end if;
   end Sync_Nvram_Block;

end Schild_Nvram_Manager;
