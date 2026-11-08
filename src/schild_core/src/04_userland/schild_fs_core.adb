-- Schild TCB — provable SchildFS on-disk parsing core (P3 input path).

package body Schild_Fs_Core with SPARK_Mode => On is

   -- CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320).
   function CRC32 (Data : Block_Buf; Len : Natural) return Unsigned_32 is
      Crc : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for I in 0 .. Len - 1 loop
         Crc := Crc xor Unsigned_32 (Data (I));
         for J in 1 .. 8 loop
            if (Crc and 1) = 1 then
               Crc := Shift_Right (Crc, 1) xor 16#EDB8_8320#;
            else
               Crc := Shift_Right (Crc, 1);
            end if;
         end loop;
      end loop;
      return not Crc;
   end CRC32;

   -- Parse the superblock header (little-endian, bytes 0..35).
   procedure Bytes_To_Superblock (Raw : Block_Buf; SB : out Superblock) is
   begin
      SB.Magic := Unsigned_32 (Raw (0)) or Shift_Left (Unsigned_32 (Raw (1)), 8)
        or Shift_Left (Unsigned_32 (Raw (2)), 16)
        or Shift_Left (Unsigned_32 (Raw (3)), 24);
      SB.Version := Unsigned_16 (Raw (4)) or Shift_Left (Unsigned_16 (Raw (5)), 8);
      SB.Block_Size := 512;
      SB.Root_Dir_LBA := Unsigned_32 (Raw (8)) or Shift_Left (Unsigned_32 (Raw (9)), 8)
        or Shift_Left (Unsigned_32 (Raw (10)), 16)
        or Shift_Left (Unsigned_32 (Raw (11)), 24);
      SB.Root_Entries := Unsigned_32 (Raw (12)) or Shift_Left (Unsigned_32 (Raw (13)), 8)
        or Shift_Left (Unsigned_32 (Raw (14)), 16)
        or Shift_Left (Unsigned_32 (Raw (15)), 24);
      SB.Checksum := Unsigned_32 (Raw (16)) or Shift_Left (Unsigned_32 (Raw (17)), 8)
        or Shift_Left (Unsigned_32 (Raw (18)), 16)
        or Shift_Left (Unsigned_32 (Raw (19)), 24);
      SB.Dir_Checksum := Unsigned_32 (Raw (20)) or Shift_Left (Unsigned_32 (Raw (21)), 8)
        or Shift_Left (Unsigned_32 (Raw (22)), 16)
        or Shift_Left (Unsigned_32 (Raw (23)), 24);
      SB.Generation := Unsigned_32 (Raw (24)) or Shift_Left (Unsigned_32 (Raw (25)), 8)
        or Shift_Left (Unsigned_32 (Raw (26)), 16)
        or Shift_Left (Unsigned_32 (Raw (27)), 24);
      SB.Next_Free_LBA := Unsigned_32 (Raw (28)) or Shift_Left (Unsigned_32 (Raw (29)), 8)
        or Shift_Left (Unsigned_32 (Raw (30)), 16)
        or Shift_Left (Unsigned_32 (Raw (31)), 24);
      SB.Block_Bitmap := Unsigned_32 (Raw (32)) or Shift_Left (Unsigned_32 (Raw (33)), 8)
        or Shift_Left (Unsigned_32 (Raw (34)), 16)
        or Shift_Left (Unsigned_32 (Raw (35)), 24);
      -- H61: parse Hmac_Key (448..479) and Hmac_Tag (480..511), little-endian.
      for W in 0 .. 3 loop
         declare
            V : Unsigned_64 := 0;
         begin
            for B in 0 .. 7 loop
               V := V or Shift_Left (Unsigned_64 (Raw (448 + W * 8 + B)), 8 * B);
            end loop;
            SB.Hmac_Key (W) := V;
         end;
      end loop;
      for W in 0 .. 3 loop
         declare
            V : Unsigned_64 := 0;
         begin
            for B in 0 .. 7 loop
               V := V or Shift_Left (Unsigned_64 (Raw (480 + W * 8 + B)), 8 * B);
            end loop;
            SB.Hmac_Tag (W) := V;
         end;
      end loop;
   end Bytes_To_Superblock;

   -- Serialize the superblock header (little-endian, bytes 0..35, rest 0).
   procedure Superblock_To_Bytes (SB : Superblock; Raw : out Block_Buf) is
   begin
      Raw := (others => 0);
      Raw (0) := Unsigned_8 (SB.Magic and 255);
      Raw (1) := Unsigned_8 (Shift_Right (SB.Magic, 8) and 255);
      Raw (2) := Unsigned_8 (Shift_Right (SB.Magic, 16) and 255);
      Raw (3) := Unsigned_8 (Shift_Right (SB.Magic, 24) and 255);
      Raw (4) := Unsigned_8 (SB.Version and 255);
      Raw (5) := Unsigned_8 (Shift_Right (SB.Version, 8) and 255);
      Raw (6) := Unsigned_8 (SB.Block_Size and 255);
      Raw (7) := Unsigned_8 (Shift_Right (SB.Block_Size, 8) and 255);
      Raw (8) := Unsigned_8 (SB.Root_Dir_LBA and 255);
      Raw (9) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 8) and 255);
      Raw (10) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 16) and 255);
      Raw (11) := Unsigned_8 (Shift_Right (SB.Root_Dir_LBA, 24) and 255);
      Raw (12) := Unsigned_8 (SB.Root_Entries and 255);
      Raw (13) := Unsigned_8 (Shift_Right (SB.Root_Entries, 8) and 255);
      Raw (14) := Unsigned_8 (Shift_Right (SB.Root_Entries, 16) and 255);
      Raw (15) := Unsigned_8 (Shift_Right (SB.Root_Entries, 24) and 255);
      Raw (16) := Unsigned_8 (SB.Checksum and 255);
      Raw (17) := Unsigned_8 (Shift_Right (SB.Checksum, 8) and 255);
      Raw (18) := Unsigned_8 (Shift_Right (SB.Checksum, 16) and 255);
      Raw (19) := Unsigned_8 (Shift_Right (SB.Checksum, 24) and 255);
      Raw (20) := Unsigned_8 (SB.Dir_Checksum and 255);
      Raw (21) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 8) and 255);
      Raw (22) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 16) and 255);
      Raw (23) := Unsigned_8 (Shift_Right (SB.Dir_Checksum, 24) and 255);
      Raw (24) := Unsigned_8 (SB.Generation and 255);
      Raw (25) := Unsigned_8 (Shift_Right (SB.Generation, 8) and 255);
      Raw (26) := Unsigned_8 (Shift_Right (SB.Generation, 16) and 255);
      Raw (27) := Unsigned_8 (Shift_Right (SB.Generation, 24) and 255);
      Raw (28) := Unsigned_8 (SB.Next_Free_LBA and 255);
      Raw (29) := Unsigned_8 (Shift_Right (SB.Next_Free_LBA, 8) and 255);
      Raw (30) := Unsigned_8 (Shift_Right (SB.Next_Free_LBA, 16) and 255);
      Raw (31) := Unsigned_8 (Shift_Right (SB.Next_Free_LBA, 24) and 255);
      Raw (32) := Unsigned_8 (SB.Block_Bitmap and 255);
      Raw (33) := Unsigned_8 (Shift_Right (SB.Block_Bitmap, 8) and 255);
      Raw (34) := Unsigned_8 (Shift_Right (SB.Block_Bitmap, 16) and 255);
      Raw (35) := Unsigned_8 (Shift_Right (SB.Block_Bitmap, 24) and 255);
      -- H61: serialize Hmac_Key (448..479) and Hmac_Tag (480..511), little-endian.
      for W in 0 .. 3 loop
         declare
            V : Unsigned_64 := SB.Hmac_Key (W);
         begin
            for B in 0 .. 7 loop
               Raw (448 + W * 8 + B) := Unsigned_8 (V and 16#FF#);
               V := Shift_Right (V, 8);
            end loop;
         end;
      end loop;
      for W in 0 .. 3 loop
         declare
            V : Unsigned_64 := SB.Hmac_Tag (W);
         begin
            for B in 0 .. 7 loop
               Raw (480 + W * 8 + B) := Unsigned_8 (V and 16#FF#);
               V := Shift_Right (V, 8);
            end loop;
         end;
      end loop;
   end Superblock_To_Bytes;

   -- Parse one 32-byte directory entry at offset Off.
   procedure Bytes_To_Dir_Entry
     (Raw : Block_Buf; Off : Natural; Ent : out Dir_Entry) is
   begin
      Ent := (Name => (others => ' '), Start_LBA => 0, Size => 0, Checksum => 0);
      for I in 0 .. 23 loop
         declare
            C : constant Unsigned_8 := Raw (Off + I);
         begin
            if C in 16#20# .. 16#7E# then
               Ent.Name (I + 1) := Character'Val (Natural (C));
            else
               Ent.Name (I + 1) := ' ';
            end if;
         end;
      end loop;
      Ent.Start_LBA := Unsigned_32 (Raw (Off + 24))
        or Shift_Left (Unsigned_32 (Raw (Off + 25)), 8)
        or Shift_Left (Unsigned_32 (Raw (Off + 26)), 16)
        or Shift_Left (Unsigned_32 (Raw (Off + 27)), 24);
      Ent.Size := Unsigned_32 (Raw (Off + 28))
        or Shift_Left (Unsigned_32 (Raw (Off + 29)), 8)
        or Shift_Left (Unsigned_32 (Raw (Off + 30)), 16)
        or Shift_Left (Unsigned_32 (Raw (Off + 31)), 24);
      Ent.Checksum := Unsigned_32 (Raw (Off + 32))
        or Shift_Left (Unsigned_32 (Raw (Off + 33)), 8)
        or Shift_Left (Unsigned_32 (Raw (Off + 34)), 16)
        or Shift_Left (Unsigned_32 (Raw (Off + 35)), 24);
   end Bytes_To_Dir_Entry;

   -- Serialize one 32-byte directory entry at offset Off.
   procedure Dir_Entry_To_Bytes
     (Ent : Dir_Entry; Raw : in out Block_Buf; Off : Natural) is
   begin
      for I in 0 .. 23 loop
         Raw (Off + I) := Unsigned_8 (Character'Pos (Ent.Name (I + 1)));
      end loop;
      Raw (Off + 24) := Unsigned_8 (Ent.Start_LBA and 255);
      Raw (Off + 25) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 8) and 255);
      Raw (Off + 26) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 16) and 255);
      Raw (Off + 27) := Unsigned_8 (Shift_Right (Ent.Start_LBA, 24) and 255);
      Raw (Off + 28) := Unsigned_8 (Ent.Size and 255);
      Raw (Off + 29) := Unsigned_8 (Shift_Right (Ent.Size, 8) and 255);
      Raw (Off + 30) := Unsigned_8 (Shift_Right (Ent.Size, 16) and 255);
      Raw (Off + 31) := Unsigned_8 (Shift_Right (Ent.Size, 24) and 255);
      Raw (Off + 32) := Unsigned_8 (Ent.Checksum and 255);
      Raw (Off + 33) := Unsigned_8 (Shift_Right (Ent.Checksum, 8) and 255);
      Raw (Off + 34) := Unsigned_8 (Shift_Right (Ent.Checksum, 16) and 255);
      Raw (Off + 35) := Unsigned_8 (Shift_Right (Ent.Checksum, 24) and 255);
   end Dir_Entry_To_Bytes;

end Schild_Fs_Core;
