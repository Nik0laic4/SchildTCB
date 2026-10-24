with Interfaces; use Interfaces;

package Schild_Hardware with SPARK_Mode is

   VGA_Width  : constant := 80;
   VGA_Height : constant := 25;
   MMIO_Size  : constant := VGA_Width * VGA_Height * 2; -- 4000

   type MMIO_Index is range 1 .. MMIO_Size + 2; --  Cursor range over the MMIO screen.
   subtype Valid_Cursor is MMIO_Index range 1 .. MMIO_Size + 2;

   type Hardware_Byte is mod 256;
   type Video_Memory_Type is array (MMIO_Index) of Hardware_Byte;

   type VGA_Screen is record
      Memory : Video_Memory_Type := (others => 0);
      Cursor : Valid_Cursor       := 1;
   end record;

   --  Write a character to the screen.
   procedure Write_Char
     (Screen : in out VGA_Screen;
      Char   :        Hardware_Byte;
      Color  :        Hardware_Byte)
   with
     Pre  => Screen.Cursor <= MMIO_Size - 1,
     Post => Screen.Cursor = Screen.Cursor'Old + 2;

end Schild_Hardware;
