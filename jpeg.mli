type array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type rgb_array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(* [array_of_string frame_string] converts the string frame_string to
   a sequence of bytes in array_frame *)
val array_of_string : string -> array_frame

external decode : array_frame -> rgb_array_frame = "jpeg_decode"
