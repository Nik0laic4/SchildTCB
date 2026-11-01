-- Schild TCB — provable HTTP/1.0 parsing core (P1 input path).
--
-- Extracted from Schild_Http_Server so the request parser can be proved at
-- SPARK Level 4 (threat model T1: the HTTP parser is the remote attacker P1's
-- direct entry point). Constrained buffer/pattern types avoid the prover
-- limitation of unconstrained String (index Positive) loops (gotcha §4.5).

with Interfaces; use Interfaces;
with Schild_Net_Types;

package Schild_Http_Core with SPARK_Mode => On is

   Max_Path_Len : constant := 24;
   subtype Path_String is String (1 .. Max_Path_Len);

   Max_Request_Len : constant := 1024;
   subtype Request_Buffer is Schild_Net_Types.Byte_Array (0 .. Max_Request_Len - 1);

   -- Bounded pattern for prefix matching (space-padded fixed width).
   Max_Pattern_Len : constant := 12;
   subtype Pattern is String (1 .. Max_Pattern_Len);

   -- True when the first P_Len bytes of B equal P(1 .. P_Len).
   function Str_Match
     (B : Request_Buffer; Request_Len : Integer; P : Pattern; P_Len : Integer)
     return Boolean
     with Pre => Request_Len in 0 .. Max_Request_Len
                 and P_Len in 0 .. Max_Pattern_Len;

   -- Parse "GET /path ..." from the first Request_Len bytes; falls back to
   -- "index.html" when the request is not a well-formed "GET /". Memory-safe
   -- for any Request_Len in 5 .. Max_Request_Len.
   function Extract_Path (B : Request_Buffer; Request_Len : Integer) return Path_String
     with Pre => Request_Len in 5 .. Max_Request_Len;

   function Is_Debug_Path (P : Path_String) return Boolean;

   subtype Byte_Array is Schild_Net_Types.Byte_Array;

   function Digit_Count (V : Unsigned_32) return Integer
     with Post => Digit_Count'Result in 1 .. 10;

   -- Write the decimal representation of V at B(Idx..), advancing Idx by
   -- Digit_Count(V). The Pre guarantees the write stays inside B.
   procedure Write_U32_Dec
     (B : out Byte_Array; Idx : in out Integer; V : Unsigned_32)
     with Pre  => Idx in B'First .. B'Last
                  and then Idx + Digit_Count (V) - 1 <= B'Last,
          Post => Idx = Idx'Old + Digit_Count (V),
          Relaxed_Initialization => B;

   -- Write S (as bytes) at B(Idx..), advancing Idx by S'Length.
   procedure Write_Str
     (B : out Byte_Array; Idx : in out Integer; S : String)
     with Pre  => Idx in B'First .. B'Last
                  and then S'Length <= B'Length
                  and then Idx + S'Length - 1 <= B'Last,
          Post => Idx = Idx'Old + S'Length,
          Relaxed_Initialization => B;

end Schild_Http_Core;