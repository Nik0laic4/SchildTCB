--  Framebuffer console body (scaffold).

with System;
with System.Storage_Elements;
with Interfaces;

package body Schild_Framebuffer is

   use Interfaces;

   Fb_Width  : Unsigned_32 := 0;
   Fb_Height : Unsigned_32 := 0;
   Fb_Pitch  : Unsigned_32 := 0;
   Cur_X     : Natural := 0;
   Cur_Y     : Natural := 0;
   Max_Cols  : Natural := 0;
   Max_Rows  : Natural := 0;
   Active    : Boolean := False;

   Green : constant Unsigned_32 := 16#0000FF00#;
   Black : constant Unsigned_32 := 16#00000000#;

   procedure Init_Fb (Addr : System.Address; W, H, Pitch, Bpp : Interfaces.Unsigned_32) is
      pragma Unreferenced (Bpp);
   begin
      if W = 0 or else H = 0 or else W > 8192 or else H > 8192 then return; end if;
      Fb_Width  := W; Fb_Height := H; Fb_Pitch := Pitch;
      Max_Cols := Natural (W / 8);
      Max_Rows := Natural (H / 16);
      Cur_X := 0; Cur_Y := 0;
      Active  := True;

      declare
         procedure C_Init (A : System.Address; Ww, Hh, Pp : Unsigned_32);
         pragma Import (C, C_Init, "schild_fb_init");
      begin
         C_Init (Addr, W, H, Pitch);
      end;
   end Init_Fb;

   procedure Put_Char (C : Character) is
      CI : constant Integer := Character'Pos (C) - 32;
      R  : Unsigned_8;
   begin
      if not Active then return; end if;

      if C = ASCII.LF then Cur_X := 0; Cur_Y := Cur_Y + 1;
         if Cur_Y >= Max_Rows then C_Scroll (16, Fb_Height, Fb_Pitch); Cur_Y := Cur_Y - 1; end if;
         return; end if;
      if C = ASCII.CR then Cur_X := 0; return; end if;
      if CI < 0 or else CI > 94 then return; end if;
      if Cur_X + 1 >= Max_Cols then Cur_X := 0; Cur_Y := Cur_Y + 1;
         if Cur_Y >= Max_Rows then C_Scroll (16, Fb_Height, Fb_Pitch); Cur_Y := Cur_Y - 1; end if; end if;

      for Row_Idx in 0 .. 15 loop
         R := Font_8x16 (Row_Idx, CI);
         for Col_Idx in 0 .. 7 loop
            if (R and Shift_Right (16#80#, Col_Idx)) /= 0 then
               C_PutPixel (Unsigned_32 (Cur_X * 8 + Col_Idx),
                           Unsigned_32 (Cur_Y * 16 + Row_Idx), Green);
            else
               C_PutPixel (Unsigned_32 (Cur_X * 8 + Col_Idx),
                           Unsigned_32 (Cur_Y * 16 + Row_Idx), Black);
            end if;
         end loop;
      end loop;
      Cur_X := Cur_X + 1;
   end Put_Char;

   procedure Put_Line (Msg : String) is
   begin
      if not Active then return; end if;
      for I in Msg'Range loop Put_Char (Msg (I)); end loop;
      Put_Char (ASCII.LF);
   end Put_Line;

   --  (C helpers perform pixel writes and scrolling.)

end Schild_Framebuffer;