--  Schild TCB - framebuffer console.
--  Text-mode output over a pixel framebuffer (font + pixel/scroll helpers in C).

with System;
with Interfaces;

package Schild_Framebuffer with
  SPARK_Mode => Off
is
   --  Initialise the framebuffer with dimensions and pitch.
   procedure Init_Fb (Addr : System.Address; W, H, Pitch, Bpp : Interfaces.Unsigned_32);

   procedure Put_Char (C : Character);
   procedure Put_Line (Msg : String);

private
   Char_Width  : constant := 8;
   Char_Height : constant := 16;

   --  Plot one pixel (imported C helper).
   procedure C_PutPixel (X, Y : Interfaces.Unsigned_32; Color : Interfaces.Unsigned_32);
   pragma Import (C, C_PutPixel, "schild_fb_putpixel");

   procedure C_Scroll (CharH, FbH, FbP : Interfaces.Unsigned_32);
   pragma Import (C, C_Scroll, "schild_fb_scroll");

   --  8x16 console font glyphs (imported C array).
   Font_8x16 : array (0 .. 15, 0 .. 94) of Interfaces.Unsigned_8;
   pragma Import (C, Font_8x16, "schild_fb_font");
end Schild_Framebuffer;