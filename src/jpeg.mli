type array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type 'a rgb_array_frame = ('a, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(* [array_of_string frame_string] converts the string frame_string to
   a sequence of bytes in array_frame *)
val array_of_string : string -> array_frame

type ('a, 'format) image = {
  image_width	   : int;
  image_height	   : int;
  image_rgb_format : 'format;
  image_data	   : 'a rgb_array_frame;
}

type 'a pixel_format
type rgb3
type rgb4

val rgb3 : rgb3 pixel_format
val rgb4 : rgb4 pixel_format

external decode_char : 'rgb pixel_format -> array_frame -> (char, 'format) image option = "jpeg_decode"
external decode_int : 'rgb pixel_format -> array_frame -> (int, 'format) image option = "jpeg_decode"
