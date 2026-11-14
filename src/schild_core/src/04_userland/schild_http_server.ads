-- Schild TCB Stage 7.9: HTTP/1.0 Server

with Interfaces; with Schild_Net_Types;

package Schild_Http_Server with SPARK_Mode => Off is
   use Interfaces;

   subtype Byte_Array is Schild_Net_Types.Byte_Array;

   -- Audit H91 / H87: in the seL4 build the NVMe controller belongs to the FS
   -- daemon, so the NetServer's HTTP server has no local filesystem; static
   -- requests answer 503 instead of reading an unmapped BAR0 and faulting.
   -- Local_FS is a compile-time constant False in the NetServer.

   procedure Handle_Request (Request : in Byte_Array;
     Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16; Success : out Boolean)
     with Pre => Reply_Buf'Length >= 4096;
end Schild_Http_Server;
