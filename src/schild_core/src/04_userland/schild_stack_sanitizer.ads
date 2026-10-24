with Interfaces; use Interfaces;

package Schild_Stack_Sanitizer with
  SPARK_Mode => On
is

   type User_Stack_Pointer is new Interfaces.Unsigned_64;
   
   type Sanitizer_Passport_Record is record
      Base_Rsp        : User_Stack_Pointer := 0;
      Random_Offset   : Interfaces.Unsigned_32 := 0;
      Is_Sanitized    : Boolean := False;
   end record;

   procedure Sanitize_And_Randomize_Stack
     (Passport : in out Sanitizer_Passport_Record;
      Success  :    out Boolean)
   with Pre => Passport.Base_Rsp /= 0,
        Post => (if Success then Passport.Is_Sanitized);

end Schild_Stack_Sanitizer;
