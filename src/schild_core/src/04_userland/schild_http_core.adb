package body Schild_Http_Core with SPARK_Mode => On is

   -- "GET /" padded to the pattern width.
   Get_Prefix : constant Pattern := "GET /       ";

   function Str_Match
     (B : Request_Buffer; Request_Len : Integer; P : Pattern; P_Len : Integer)
     return Boolean
   is
   begin
      if P_Len > Request_Len then
         return False;
      end if;
      for K in 0 .. P_Len - 1 loop
         pragma Loop_Invariant (K in 0 .. P_Len - 1);
         if B (K) /= Character'Pos (P (K + 1)) then
            return False;
         end if;
      end loop;
      return True;
   end Str_Match;

   function Extract_Path (B : Request_Buffer; Request_Len : Integer) return Path_String is
      Fn     : Path_String := (others => ' ');
      Fn_Pos : Integer := 1;
   begin
      if not Str_Match (B, Request_Len, Get_Prefix, 5) then
         Fn (1 .. 10) := "index.html";
         return Fn;
      end if;
      --  Read the path (starts at byte 5, after "GET /") up to the first space.
      for K in 5 .. Request_Len - 1 loop
         pragma Loop_Invariant (Fn_Pos in 1 .. Max_Path_Len + 1);
         exit when B (K) = 32;
         exit when Fn_Pos > Max_Path_Len;
         if B (K) >= 32 and B (K) <= 126 then
            Fn (Fn_Pos) := Character'Val (B (K));
            Fn_Pos := Fn_Pos + 1;
         end if;
      end loop;
      if Fn_Pos = 1 then
         Fn (1 .. 10) := "index.html";
      end if;
      return Fn;
   end Extract_Path;

   function Is_Debug_Path (P : Path_String) return Boolean is
      Debug      : constant String := "debug";
      Debug_Html : constant String := "debug.html";
   begin
      --  Match "/debug" or "/debug.html" (the fixed-width path is space-padded).
      if P (1 .. Debug_Html'Length) = Debug_Html then
         return True;
      elsif P (1 .. Debug'Length) = Debug
        and then P (Debug'Length + 1) = ' '
      then
         return True;
      end if;
      return False;
   end Is_Debug_Path;

   function Digit_Count (V : Unsigned_32) return Integer is
   begin
      if V >= 1_000_000_000 then
         return 10;
      elsif V >= 100_000_000 then
         return 9;
      elsif V >= 10_000_000 then
         return 8;
      elsif V >= 1_000_000 then
         return 7;
      elsif V >= 100_000 then
         return 6;
      elsif V >= 10_000 then
         return 5;
      elsif V >= 1_000 then
         return 4;
      elsif V >= 100 then
         return 3;
      elsif V >= 10 then
         return 2;
      else
         return 1;
      end if;
   end Digit_Count;

   procedure Write_U32_Dec (B : out Byte_Array; Idx : in out Integer; V : Unsigned_32) is
      D   : constant Integer := Digit_Count (V);
      Val : Unsigned_32 := V;
   begin
      --  Emit the D decimal digits of V right-to-left into B(Idx .. Idx + D - 1).
      for K in 0 .. D - 1 loop
         pragma Loop_Invariant (K in 0 .. D - 1);
         B (Idx + D - 1 - K) := 48 + Unsigned_8 (Val rem 10);
         Val := Val / 10;
      end loop;
      Idx := Idx + D;
   end Write_U32_Dec;

   procedure Write_Str (B : out Byte_Array; Idx : in out Integer; S : String) is
   begin
      for I in S'Range loop
         pragma Loop_Invariant (Idx - Idx'Loop_Entry = I - S'First);
         B (Idx) := Character'Pos (S (I));
         Idx := Idx + 1;
      end loop;
   end Write_Str;

end Schild_Http_Core;