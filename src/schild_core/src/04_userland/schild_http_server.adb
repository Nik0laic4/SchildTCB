-- Schild TCB Stage 7.9: HTTP Server — body
with System; with Interfaces;
with Schild_Uart_Driver; with Schild_Schild_Fs; with Schild_Http_Core;

package body Schild_Http_Server with SPARK_Mode => Off is
   use Interfaces;

   -- Fixed-width filename/path lives in Schild_Http_Core.Path_String (proved).

   --  Hard cap on the incoming HTTP request size: reject anything larger
   --  before parsing, keeping primitive fuzzing out of the Ada path.
   Max_Header_Len : constant Integer := 1024;

   procedure C_Putln (Addr : System.Address; Len : Integer);
   pragma Import (C, C_Putln, "schild_uart_putln");

   -- Audit H91: True in the standalone kernel (NVMe + SchildFS live in the same
   -- address space).  False in the seL4 NetServer, where the FS daemon owns the
   -- controller: the FS body would read 0x620000 in a VSpace that never mapped
   -- it, so the request handler must not call it at all.
   -- H87: the HTTP server is NetServer-only; the NetServer never owns the NVMe,
   -- so Local_FS is a compile-time constant False and the static-file branch is
   -- removed. Static requests answer 503 (a future IPC path may serve them).
   Local_FS : constant Boolean := False;

   -- Stage 9: network debug observability — C-bridge into the audit log.
   -- The real renderer lives in the NetServer runtime; the standalone kernel
   -- links a no-op stub, so the core build footprint stays at 182 objects.
   procedure Schild_Debug_Render
     (Buffer     : System.Address;
      Max_Len    : Natural;
      Actual_Len : out Natural);
   pragma Import (C, Schild_Debug_Render, "schild_debug_render");

   procedure Handle_Request
     (Request   : in     Byte_Array;
      Reply_Buf :    out Byte_Array;
      Reply_Len :    out Unsigned_16;
      Success   :    out Boolean)
   is
      Path    : Schild_Http_Core.Path_String := (others => ' ');
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
      -- Audit H91: no local FS in this process (NVMe owned by the FS daemon).
      Http_503 : constant String := "HTTP/1.0 503 Service Unavailable" & ASCII.CR & ASCII.LF
        & "Content-Type: text/plain" & ASCII.CR & ASCII.LF
        & "Connection: close" & ASCII.CR & ASCII.LF
        & "Content-Length: 35" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF
        & "503 static file service unavailable";
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

      -- Audit C23: Pre Reply_Buf'Length >= 4096 not enforced at Off callers.
      -- Guard before any Write_Str to prevent OOB on undersized buffer.
      if Reply_Buf'Length < 4096 then
         return;
      end if;

      --  Primitive-fuzz guard: reject oversized request headers outright.
      if Request'Length > Max_Header_Len then
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_Too_Long);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      -- Parse the path through the proven core (memory-safe on 5..1024 bytes).
      if Request'Length < 5 then
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_404);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;
      declare
         Req : Schild_Http_Core.Request_Buffer := (others => 0);
      begin
         for J in Request'Range loop
            Req (J - Request'First) := Request (J);
         end loop;
         Path := Schild_Http_Core.Extract_Path (Req, Request'Length);
      end;

      -- Stage 9: GET /debug (and /debug.html) serve the hardware audit log
      -- through the C-bridge, never through SchildFS.
      if Schild_Http_Core.Is_Debug_Path (Path) then
         declare
            Html_Head : constant String :=
              "<html><body><h1>Schild TCB Hardware Debug Log</h1><pre>";
            Html_Tail : constant String := "</pre></body></html>";
            Written   : Natural := 0;
         begin
            --  HTTP 200 header (text/html) with a 5-digit Content-Length slot.
            Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_200);
            Body_Start := Idx;
            for J in 1 .. 5 loop Reply_Buf (Idx) := 32; Idx := Idx + 1; end loop;
            Schild_Http_Core.Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
            Body_Start := Idx;

            --  HTML body: prefix + audit log text (C-bridge) + suffix.
            Schild_Http_Core.Write_Str (Reply_Buf, Idx, Html_Head);
            Schild_Debug_Render
              (Reply_Buf (Idx)'Address,
               Reply_Buf'Last - Idx + 1,
               Written);
            Idx := Idx + Integer (Written);
            Schild_Http_Core.Write_Str (Reply_Buf, Idx, Html_Tail);

            --  Fix Content-Length.
            declare
               Body_Len : constant Unsigned_32 := Unsigned_32 (Idx - Body_Start);
               Tmp : Integer := Body_Start - 4 - Schild_Http_Core.Digit_Count (Body_Len);
            begin
               Schild_Http_Core.Write_U32_Dec (Reply_Buf, Tmp, Body_Len);
            end;

            Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
            Success := True;
            return;
         end;
      end if;

      -- Built-in landing page for GET / (no filesystem required).
      if Path (1 .. 10) = "index.html" then
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_200);
         Schild_Http_Core.Write_U32_Dec (Reply_Buf, Idx, Unsigned_32 (Index_Html'Length));
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Index_Html);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      -- Audit H91: the FS body is only usable when this process owns NVMe.
      -- In the seL4 NetServer it does not, and touching SchildFS would fault on
      -- the unmapped BAR0.  Answer 503 instead of lying with a 404 or crashing.
      if not Local_FS then
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_503);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      declare
         File    : Schild_Schild_Fs.File_Info;
         FS_OK   : Boolean;
         Data_Buf: Schild_Schild_Fs.Unsigned_8_Array (0 .. 4095);
         Data_Len: Unsigned_32;
      begin
      if not Schild_Schild_Fs.Is_Mounted then
         Schild_Schild_Fs.Init (FS_OK);
      end if;

      Schild_Schild_Fs.Open (Path, File, FS_OK);

      if not FS_OK then
         Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_404);
         Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
         Success := True;
         return;
      end if;

      -- Write HTTP 200 header
      Schild_Http_Core.Write_Str (Reply_Buf, Idx, Http_200);
      Body_Start := Idx;
      -- Reserve space for Content-Length (placeholder, will be overwritten)
      for J in 1 .. 5 loop Reply_Buf (Idx) := 32; Idx := Idx + 1; end loop;
      Schild_Http_Core.Write_Str (Reply_Buf, Idx, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);

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
      end;

      -- Fix Content-Length
      declare
         Body_Len : constant Unsigned_32 := Unsigned_32 (Idx - Body_Start);
         Tmp : Integer := Body_Start - 4 - Schild_Http_Core.Digit_Count (Body_Len);
      begin
         Schild_Http_Core.Write_U32_Dec (Reply_Buf, Tmp, Body_Len);
      end;

      Reply_Len := Unsigned_16 (Idx - Reply_Buf'First);
      Success := True;
   end Handle_Request;

end Schild_Http_Server;
