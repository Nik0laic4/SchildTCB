--  Schild TCB - IDT loader body.
--  Builds a 256-gate interrupt descriptor table and installs it with LIDT.

with System.Machine_Code;
with System;
with Interfaces;
with System.Storage_Elements;

package body Schild_Idt_Loader with
  SPARK_Mode => Off  --  Inline assembly (LIDT) and packed records are outside SPARK.
is
   use Interfaces;

   --  A 64-bit interrupt gate (16 bytes, two 32-bit offset halves).
   type Idt_Gate is record
      Offset_Low  : Unsigned_16;  --  Low 16 bits of the handler address.
      Selector    : Unsigned_16;  --  Code segment selector.
      IST         : Unsigned_8;   -- Interrupt Stack Table (0 = none)
      Attributes  : Unsigned_8;   -- P(1) DPL(2) 0(1) Type(4) = 0x8E
      Offset_Mid  : Unsigned_16;  --  Next 16 bits of the handler address.
      Offset_High : Unsigned_32;  --  High 32 bits of the handler address.
      Reserved    : Unsigned_32;  --  Must be zero.
   end record;

   for Idt_Gate use record
      Offset_Low  at 0 range 0 .. 15;
      Selector    at 2 range 0 .. 15;
      IST         at 4 range 0 .. 7;
      Attributes  at 5 range 0 .. 7;
      Offset_Mid  at 6 range 0 .. 15;
      Offset_High at 8 range 0 .. 31;
      Reserved    at 12 range 0 .. 31;
   end record;

   for Idt_Gate'Size use 128;

   --  The full 256-entry interrupt descriptor table.
   type Idt_Table is array (Unsigned_32 range 0 .. 255) of Idt_Gate;
   pragma Pack (Idt_Table);

   --  The 10-byte IDTR descriptor (limit + base).
   type Idt_Descriptor is record
      Limit : Unsigned_16;
      Base  : Unsigned_64;
   end record;
   for Idt_Descriptor use record
      Limit at 0 range 0 .. 15;
      Base  at 2 range 0 .. 63;
   end record;
   for Idt_Descriptor'Size use 80;

   --  The table itself, zeroed initially.
   IDT : Idt_Table := (others =>
     (Offset_Low => 0, Selector => 0, IST => 0,
      Attributes => 0, Offset_Mid => 0,
      Offset_High => 0, Reserved => 0));

   Idt_Desc : Idt_Descriptor;

   -------------------------------
   --  Init_Idt
   -------------------------------
   procedure Init_Idt is
      Idt_Addr : constant System.Address := IDT'Address;
   begin
      --  Fill the IDTR with the table's limit and base address.
      Idt_Desc.Limit := Unsigned_16 (Idt_Table'Size / 8 - 1);
      Idt_Desc.Base  := Unsigned_64 (System.Storage_Elements.To_Integer (Idt_Addr));

      --  Load the IDT into the CPU (LIDT).
      System.Machine_Code.Asm
        (Template => "lidt %0",
         Inputs   => Idt_Descriptor'Asm_Input ("m", Idt_Desc),
         Volatile => True);
   end Init_Idt;

   -------------------------------
   -- Set_Gate
   -------------------------------
   procedure Set_Gate
     (Vector   : in Unsigned_32;
      Handler  : in System.Address;
      DPL      : in Unsigned_8 := 0)
   is
      Handler_Addr : constant Unsigned_64 :=
        Unsigned_64 (System.Storage_Elements.To_Integer (Handler));
      Attr : constant Unsigned_8 :=
        16#8E# or Shift_Left (DPL and 3, 5);  -- Present + Type=Interrupt Gate
   begin
      if Vector > 255 then return; end if;

      IDT (Vector) :=
        (Offset_Low  => Unsigned_16 (Handler_Addr and 16#FFFF#),
         Selector    => 16#08#,              -- Kernel Code Segment
         IST         => 0,
         Attributes  => Attr,
         Offset_Mid  => Unsigned_16 (Shift_Right (Handler_Addr, 16) and 16#FFFF#),
         Offset_High => Unsigned_32 (Shift_Right (Handler_Addr, 32) and 16#FFFF_FFFF#),
         Reserved    => 0);
   end Set_Gate;

end Schild_Idt_Loader;
