pragma Spark_Mode (On);

package body Schild_Page_Flags_Guard is

   procedure Check_Page_Flags
     (Flags      : in     Interfaces.Unsigned_64;
      Seg_Class  : in     Segment_Class_Type;
      Is_Trusted :    out Boolean)
   is
   begin
      case Seg_Class is
         when Segment_Kernel_Code =>
            --  Kernel code: present and supervisor-only.
            Is_Trusted := (Flags and 16#1#) = 16#1# and then (Flags and 16#4#) = 0;
            
         when Segment_Kernel_Data =>
            --  Kernel data: present, writable, supervisor-only.
            Is_Trusted := (Flags and 16#3#) = 16#3# and then (Flags and 16#4#) = 0;
            
         when Segment_User_Code =>
            --  User code: present and user, not writable.
            Is_Trusted := (Flags and 16#5#) = 16#5#;
            
         when Segment_User_Data =>
            --  User data: present, writable, user.
            Is_Trusted := (Flags and 16#7#) = 16#7#;
      end case;
   end Check_Page_Flags;

end Schild_Page_Flags_Guard;
