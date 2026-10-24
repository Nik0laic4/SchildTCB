-- Schild TCB Stage 7.9: HTTP Server — body
with System; with Interfaces;
with Schild_Uart_Driver; with Schild_Schild_Fs;

package body Schild_Http_Server with SPARK_Mode => Off is
   use Interfaces;

   -- Fixed-width filename (no secondary stack in the bare-metal runtime).
   subtype Path_String is String (1 .. 24);

   --  Hard cap on the incoming HTTP request size: reject anything larger
   --  before parsing, keeping primitive fuzzing out of the Ada path.
   Max_Header_Len : constant Integer := 1024;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   -- Stage 9: network debug observability — C-bridge into the audit log.
   -- The real renderer lives in the NetServer runtime; the standalone kernel
   -- links a no-op stub, so the core build footprint stays at 182 objects.
   procedure Schild_Debug_Render
     (Buffer     : System.Address;
      Max_Len    : Natural;
      Actual_Len : out Natural);
   pragma Import (C, Schild_Debug_Render, "schild_debug_render");

   function Str_Match (B : Byte_Array; Start : Integer; S : String) return Boolean is
   begin
      if Start + S'Length > B'Last + 1 then return False; end if;
      for I in S'Range loop
         if Character'Val (B (Start + I - S'First)) /= S (I) then return False; end if;
      end loop;
      return True;
   end Str_Match;

   procedure Write_Str (B : out Byte_Array; Idx : in out Integer; S : String) is
   begin
      for I in S'Range loop B (Idx) := Character'Pos (S (I)); Idx := Idx + 1; end loop;
   end Write_Str;

   procedure Write_U32_Dec (B : out Byte_Array; Idx : in out Integer; V : Unsigned_32) is
      Tmp : array (0 .. 9) of Unsigned_8;
      Pos : Integer := 9;
      Val : Unsigned_32 := V;
   begin
      if Val = 0 then Tmp (9) := 48; Pos := 9;
      else
         while Val > 0 loop
            Tmp (Pos) := 48 + Unsigned_8 (Val rem 10); Pos := Pos - 1; Val := Val / 10;
         end loop;
      end if;
      for J in Pos + 1 .. 9 loop B (Idx) := Tmp (J); Idx := Idx + 1; end loop;
   end Write_U32_Dec;

   function Digit_Count (V : Unsigned_32) return Integer is
      D : Integer := 1;
      X : Unsigned_32 := V;
   begin
      while X >= 10 loop X := X / 10; D := D + 1; end loop;
      return D;
   end Digit_Count;

   function Extract_Path (B : Byte_Array) return Path_String is
      Start : Integer := B'First;
      Fn    : Path_String := (others => ' ');
      Fn_Pos : Integer := 1;
   begin
      -- Skip "GET /"
      for I in B'Range loop
         exit when Start > B'First + 2;
         if B (I) = 32 then Start := Start + 1; end if;
      end loop;
      if not Str_Match (B, B'First, "GET /") then
         Fn (1 .. 10) := "index.html";
         return Fn;
      end if;
      -- Read path
      for I in B'First + 5 .. B'Last loop
         exit when I >= B'First + Max_Header_Len;
         exit when B (I) = 32;
         exit when Fn_Pos > 24;
         if B (I) >= 32 and B (I) <= 126 then
            Fn (Fn_Pos) := Character'Val (B (I));
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
      --  Match "/debug" or "/debug.html" (the fixed-width path is
      --  space-padded, so trailing spaces are ignored).
      if P'Length >= Debug_Html'Length
        and then P (1 .. Debug_Html'Length) = Debug_Html
      then
         return True;
      elsif P'Length >= Debug'Length
        and then P (1 .. Debug'Length) = Debug
        and then (P'Length = Debug'Length or else P (Debug'Length + 1) = ' ')
      then
         return True;
      end if;
      return False;
   end Is_Debug_Path;

   procedure Handle_Request
     (Request   : in     Byte_Array;
      Reply_Buf :    out Byte_Array;
      Reply_Len :    out Unsigned_16;
      Success   :    out Boolean)
   is
      Path    : constant Path_String := Extract_Path (Request);
      File    : Schild_Schild_Fs.File_Info;
      FS_OK   : Boolean;
      Data_Buf: Schild_Schild_Fs.Unsigned_8_Array (0 .. 4095);
      Data_Len: Unsigned_32;
      Idx     : Integer := Reply_Buf'First;
      Body_Start : Integer;
      Http_200 : constant String := "HTTP/1.0 200 OK" & ASCII.CR & ASCII.LF
        & "Content-Type: text/html; charset=utf-8" & ASCII.CR & ASCII.LF
        & "Server: Schild TCB/0.9" & ASCII.CR & ASCII.LF
        & "Connection: close" & ASCII.CR & ASCII.LF
        & "Content-Length: ";
      Http_404 : constant String := "HTTP/1.0 404 Not Found" & ASCII.CR & ASCII.LF
        & "Content-Type: text/plain" & ASCII.CR & ASCII.LF
        & "Connection: close" & ASCII.CR & ASCII.LF
        & "Content-Length: 13" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF
        & "404 Not Found";
      Http_Too_Long : constant String := "HTTP/1.0 414 URI Too Long" & ASCII.CR & ASCII.LF
        & "Content-Type: text/plain" & ASCII.CR & ASCII.LF
        & "Connection: close" & ASCII.CR & ASCII.LF
        & "Content-Length: 16" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF
        & "414 URI Too Long";
      Index_Html : constant String := "<html><body style='font-family:monospace'>"
        & "<h1>Schild TCB</h1>"
        & "<p>High-assurance research prototype (Ada/SPARK + seL4).</p>"
        & "<p>Network stack: e1000e + IPv4/ARP/ICMP/TCP + HTTP/1.0.</p>"
        & "<p><a href='/debug'>Hardware debug log</a></p>"
        & "</body></html>";

      Msg_HTTP : constant String := "[HTTP] ";
   begin
      Success := False;
      Reply_Len := 0;

      --  Primitive-fuzz guard: reject oversized request headers outright.
      if Request'Length > Max_Header_Len then
         Write_Str (Reply_Buf, Idx, Http_Too_Long);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      -- Stage 9: GET /debug (and /debug.html) serve the hardware audit log
      -- through the C-bridge, never through SchildFS.
      if Is_Debug_Path (Path) then
         declare
            Html_Head : constant String :=
              "<html><body><h1>Schild TCB Hardware Debug Log</h1><pre>";
            Html_Tail : constant String := "</pre></body></html>";
            Written   : Natural := 0;
         begin
            --  HTTP 200 header (text/html) with a 5-digit Content-Length slot.
            Write_Str (Reply_Buf, Idx, Http_200);
            Body_Start := Idx;
            for J in 1 .. 5 loop Reply_Buf (Idx) := 32; Idx := Idx + 1; end loop;
            Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
            Body_Start := Idx;

            --  HTML body: prefix + audit log text (C-bridge) + suffix.
            Write_Str (Reply_Buf, Idx, Html_Head);
            Schild_Debug_Render
              (Reply_Buf (Idx)'Address,
               Reply_Buf'Last - Idx + 1,
               Written);
            Idx := Idx + Integer (Written);
            Write_Str (Reply_Buf, Idx, Html_Tail);

            --  Fix Content-Length.
            declare
               Body_Len : constant Unsigned_32 := Unsigned_32 (Idx - Body_Start);
               Tmp : Integer := Body_Start - 4 - Digit_Count (Body_Len);
            begin
               Write_U32_Dec (Reply_Buf, Tmp, Body_Len);
            end;

            Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
            Success := True;
            return;
         end;
      end if;

      -- Built-in landing page for GET / (no filesystem required).
      if Path (1 .. 10) = "index.html" then
         Write_Str (Reply_Buf, Idx, Http_200);
         Write_U32_Dec (Reply_Buf, Idx, Unsigned_32 (Index_Html'Length));
         Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
         Write_Str (Reply_Buf, Idx, Index_Html);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      if not Schild_Schild_Fs.Is_Mounted then
         Schild_Schild_Fs.Init (FS_OK);
      end if;

      Schild_Schild_Fs.Open (Path, File, FS_OK);

      if not FS_OK then
         Write_Str (Reply_Buf, Idx, Http_404);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      -- Write HTTP 200 header
      Write_Str (Reply_Buf, Idx, Http_200);
      Body_Start := Idx;
      -- Reserve space for Content-Length (placeholder, will be overwritten)
      for J in 1 .. 5 loop Reply_Buf (Idx) := 32; Idx := Idx + 1; end loop;
      Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);

      Body_Start := Idx;

      -- Read file and write body
      loop
         Schild_Schild_Fs.Read (File, Data_Buf, Data_Len, FS_OK);
         exit when not FS_OK or Data_Len = 0;
         for J in 0 .. Integer (Data_Len) - 1 loop
            Reply_Buf (Idx) := Data_Buf (J); Idx := Idx + 1;
            exit when Idx >= Reply_Buf'Last - 50;
         end loop;
         exit when Idx >= Reply_Buf'Last - 50;
      end loop;

      -- Fix Content-Length
      declare
         Body_Len : constant Unsigned_32 := Unsigned_32 (Idx - Body_Start);
         Tmp : Integer := Body_Start - 4 - Digit_Count (Body_Len);
      begin
         Write_U32_Dec (Reply_Buf, Tmp, Body_Len);
      end;

      Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
      Success := True;
   end Handle_Request;

end Schild_Http_Server;
