package body Schild_Text with
  SPARK_Mode => On
is
   procedure Image
     (Value : Natural;
      Buf   : out Image_String;
      Len   : out Natural)
   is
      Tmp : Image_String;
      Cnt : Natural := 0;
      V   : Natural := Value;
   begin
      Tmp := (others => ' ');   --  fully define Tmp (flow analysis)
      --  Phase 1: extract digits (least significant first) into Tmp, right
      --  justified: the most significant digit ends up at Tmp (Last - Cnt + 1).
      V := Value;
      for I in 1 .. Max_Width loop
         pragma Loop_Invariant (Cnt = I - 1);
         Tmp (Image_String'Last - I + 1) := Character'Val (48 + (V mod 10));
         V   := V / 10;
         Cnt := Cnt + 1;
         exit when V = 0;
      end loop;

      --  Phase 2: copy the Cnt significant digits to the left of Buf.
      Buf := (others => ' ');
      for I in 1 .. Cnt loop
         Buf (I) := Tmp (Image_String'Last - Cnt + I);
         pragma Loop_Invariant (I >= 1 and then I <= Cnt and then Cnt <= Max_Width);
      end loop;
      Len := Cnt;
   end Image;
end Schild_Text;
