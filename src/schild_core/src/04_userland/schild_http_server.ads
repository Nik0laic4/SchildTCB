-- Schild TCB Stage 7.9: HTTP/1.0 Server

with Interfaces; with Schild_Net_Types;

package Schild_Http_Server with SPARK_Mode => Off is
   use Interfaces;

   subtype Byte_Array is Schild_Net_Types.Byte_Array;

   -- Audit H91: in the seL4 build the NVMe controller belongs to the FS daemon,
   -- so a NetServer has no filesystem in its own VSpace. The root task marks
   -- that process with Set_Local_FS (False); static requests then answer 503
   -- instead of reading an unmapped BAR0 and faulting.
   procedure Set_Local_FS (Enabled : Boolean);

   procedure Handle_Request (Request : in Byte_Array;
     Reply_Buf : out Byte_Array; Reply_Len : out Unsigned_16; Success : out Boolean)
     with Pre => Reply_Buf'Length >= 4096;
end Schild_Http_Server;
