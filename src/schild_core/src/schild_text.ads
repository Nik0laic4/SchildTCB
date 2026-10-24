-- Schild TCB — provably-bounded decimal rendering.
--
-- The hand-rolled `int → string` loops scattered across SPARK-proven modules
-- (boot runtime, firewall) had unprovable bounds and "may be uninitialized"
-- defects. This package is the single, provable replacement.

package Schild_Text with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   --  A Natural (2**31 - 1) needs at most 10 decimal digits.
   Max_Width : constant := 10;
   subtype Image_String is String (1 .. Max_Width);

   --  Left-aligned decimal image of Value into Buf, with Buf (Len + 1 .. Max_Width)
   --  blank. Buf (1 .. Len) is the significant image (no leading blanks).
   procedure Image
     (Value : Natural;
      Buf   : out Image_String;
      Len   : out Natural)
   with
     Post => Len >= 1 and then Len <= Max_Width;
end Schild_Text;
