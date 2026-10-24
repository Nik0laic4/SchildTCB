pragma Spark_Mode (Off);

with Interfaces;
use Interfaces;

package body Schild_Aes_Ni_Core is

   --  AES S-box (FIPS-197, section 5.1.1), indexed 0..255.
   SBox : constant array (Unsigned_8) of Unsigned_8 :=
     (16#63#,16#7C#,16#77#,16#7B#,16#F2#,16#6B#,16#6F#,16#C5#,
      16#30#,16#01#,16#67#,16#2B#,16#FE#,16#D7#,16#AB#,16#76#,
      16#CA#,16#82#,16#C9#,16#7D#,16#FA#,16#59#,16#47#,16#F0#,
      16#AD#,16#D4#,16#A2#,16#AF#,16#9C#,16#A4#,16#72#,16#C0#,
      16#B7#,16#FD#,16#93#,16#26#,16#36#,16#3F#,16#F7#,16#CC#,
      16#34#,16#A5#,16#E5#,16#F1#,16#71#,16#D8#,16#31#,16#15#,
      16#04#,16#C7#,16#23#,16#C3#,16#18#,16#96#,16#05#,16#9A#,
      16#07#,16#12#,16#80#,16#E2#,16#EB#,16#27#,16#B2#,16#75#,
      16#09#,16#83#,16#2C#,16#1A#,16#1B#,16#6E#,16#5A#,16#A0#,
      16#52#,16#3B#,16#D6#,16#B3#,16#29#,16#E3#,16#2F#,16#84#,
      16#53#,16#D1#,16#00#,16#ED#,16#20#,16#FC#,16#B1#,16#5B#,
      16#6A#,16#CB#,16#BE#,16#39#,16#4A#,16#4C#,16#58#,16#CF#,
      16#D0#,16#EF#,16#AA#,16#FB#,16#43#,16#4D#,16#33#,16#85#,
      16#45#,16#F9#,16#02#,16#7F#,16#50#,16#3C#,16#9F#,16#A8#,
      16#51#,16#A3#,16#40#,16#8F#,16#92#,16#9D#,16#38#,16#F5#,
      16#BC#,16#B6#,16#DA#,16#21#,16#10#,16#FF#,16#F3#,16#D2#,
      16#CD#,16#0C#,16#13#,16#EC#,16#5F#,16#97#,16#44#,16#17#,
      16#C4#,16#A7#,16#7E#,16#3D#,16#64#,16#5D#,16#19#,16#73#,
      16#60#,16#81#,16#4F#,16#DC#,16#22#,16#2A#,16#90#,16#88#,
      16#46#,16#EE#,16#B8#,16#14#,16#DE#,16#5E#,16#0B#,16#DB#,
      16#E0#,16#32#,16#3A#,16#0A#,16#49#,16#06#,16#24#,16#5C#,
      16#C2#,16#D3#,16#AC#,16#62#,16#91#,16#95#,16#E4#,16#79#,
      16#E7#,16#C8#,16#37#,16#6D#,16#8D#,16#D5#,16#4E#,16#A9#,
      16#6C#,16#56#,16#F4#,16#EA#,16#65#,16#7A#,16#AE#,16#08#,
      16#BA#,16#78#,16#25#,16#2E#,16#1C#,16#A6#,16#B4#,16#C6#,
      16#E8#,16#DD#,16#74#,16#1F#,16#4B#,16#BD#,16#8B#,16#8A#,
      16#70#,16#3E#,16#B5#,16#66#,16#48#,16#03#,16#F6#,16#0E#,
      16#61#,16#35#,16#57#,16#B9#,16#86#,16#C1#,16#1D#,16#9E#,
      16#E1#,16#F8#,16#98#,16#11#,16#69#,16#D9#,16#8E#,16#94#,
      16#9B#,16#1E#,16#87#,16#E9#,16#CE#,16#55#,16#28#,16#DF#,
      16#8C#,16#A1#,16#89#,16#0D#,16#BF#,16#E6#,16#42#,16#68#,
      16#41#,16#99#,16#2D#,16#0F#,16#B0#,16#54#,16#BB#,16#16#);

   --  Round constants for AES-128 key expansion (rounds 1..10).
   Rcon : constant array (1 .. 10) of Unsigned_8 :=
     (16#01#,16#02#,16#04#,16#08#,16#10#,16#20#,16#40#,16#80#,16#1B#,16#36#);

   type Round_Keys_Type is array (0 .. 10) of Aes_Block_Type;

   --  GF(2^8) multiply by 2 (xtime).
   function Mul2 (X : Unsigned_8) return Unsigned_8 is
      T : Unsigned_8 := Shift_Left (X, 1);
   begin
      if (X and 16#80#) /= 0 then
         T := T xor 16#1B#;
      end if;
      return T;
   end Mul2;

   --  GF(2^8) multiply by 3 = Mul2(X) xor X.
   function Mul3 (X : Unsigned_8) return Unsigned_8 is
     (Mul2 (X) xor X);

   procedure Key_Expansion
     (Key : in  Aes_Block_Type;
      RK  : out Round_Keys_Type)
   is
      W : array (0 .. 175) of Unsigned_8;
      T : array (0 .. 3) of Unsigned_8;
   begin
      for I in 0 .. 15 loop
         W (I) := Key (I);
      end loop;
      for I in 4 .. 43 loop
         for J in 0 .. 3 loop
            T (J) := W (4 * (I - 1) + J);
         end loop;
         if I mod 4 = 0 then
            --  RotWord, SubWord, then xor the round constant.
            T := (T (1), T (2), T (3), T (0));
            for J in 0 .. 3 loop
               T (J) := SBox (T (J));
            end loop;
            T (0) := T (0) xor Rcon (I / 4);
         end if;
         for J in 0 .. 3 loop
            W (4 * I + J) := W (4 * (I - 4) + J) xor T (J);
         end loop;
      end loop;
      for R in 0 .. 10 loop
         for J in 0 .. 15 loop
            RK (R) (J) := W (16 * R + J);
         end loop;
      end loop;
   end Key_Expansion;

   procedure Sub_Bytes (S : in out Aes_Block_Type) is
   begin
      for I in Aes_Block_Index loop
         S (I) := SBox (S (I));
      end loop;
   end Sub_Bytes;

   procedure Shift_Rows (S : in out Aes_Block_Type) is
      T : Aes_Block_Type := S;
   begin
      S (0) := T (0);  S (4) := T (4);  S (8) := T (8);  S (12) := T (12);
      S (1) := T (5);  S (5) := T (9);  S (9) := T (13); S (13) := T (1);
      S (2) := T (10); S (6) := T (14); S (10) := T (2); S (14) := T (6);
      S (3) := T (15); S (7) := T (3);  S (11) := T (7); S (15) := T (11);
   end Shift_Rows;

   procedure Mix_Columns (S : in out Aes_Block_Type) is
      T : Aes_Block_Type := S;
      A0, A1, A2, A3 : Unsigned_8;
   begin
      for C in 0 .. 3 loop
         A0 := T (4 * C);
         A1 := T (4 * C + 1);
         A2 := T (4 * C + 2);
         A3 := T (4 * C + 3);
         S (4 * C)     := Mul2 (A0) xor Mul3 (A1) xor A2 xor A3;
         S (4 * C + 1) := A0 xor Mul2 (A1) xor Mul3 (A2) xor A3;
         S (4 * C + 2) := A0 xor A1 xor Mul2 (A2) xor Mul3 (A3);
         S (4 * C + 3) := Mul3 (A0) xor A1 xor A2 xor Mul2 (A3);
      end loop;
   end Mix_Columns;

   procedure Add_Round_Key (S : in out Aes_Block_Type; RK : Aes_Block_Type) is
   begin
      for I in Aes_Block_Index loop
         S (I) := S (I) xor RK (I);
      end loop;
   end Add_Round_Key;

   procedure Encrypt_Aes128_Block
     (Plaintext  : in     Aes_Block_Type;
      Key        : in     Aes_Block_Type;
      Ciphertext :    out Aes_Block_Type)
   is
      RK : Round_Keys_Type;
      S  : Aes_Block_Type := Plaintext;
   begin
      Key_Expansion (Key, RK);
      Add_Round_Key (S, RK (0));
      for R in 1 .. 9 loop
         Sub_Bytes (S);
         Shift_Rows (S);
         Mix_Columns (S);
         Add_Round_Key (S, RK (R));
      end loop;
      Sub_Bytes (S);
      Shift_Rows (S);
      Add_Round_Key (S, RK (10));
      Ciphertext := S;
   end Encrypt_Aes128_Block;

end Schild_Aes_Ni_Core;
