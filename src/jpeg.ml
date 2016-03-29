type array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type 'a rgb_array_frame = ('a, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type ('a, 'format) image = {
  image_width : int;
  image_height : int;
  image_rgb_format : 'format;
  image_data : 'a rgb_array_frame;
}

(* [array_of_string frame_string] converts the string frame_string to
   a sequence of bytes in array_frame *)
let array_of_string : string -> array_frame =
  fun str ->
    let open Bigarray in
    let open Array1 in
    let ar = create char c_layout (String.length str) in
    for c = 0 to String.length str - 1 do
      unsafe_set ar c (String.unsafe_get str c)
    done;
    ar

type rgb3
type rgb4

type 'a pixel_format = {
  pf_bytes_per_pixel : int;
} 

let rgb3 = { pf_bytes_per_pixel = 3; }
let rgb4 = { pf_bytes_per_pixel = 4; }

external decode_char : 'rgb pixel_format -> array_frame -> (char, 'format) image option = "jpeg_decode"
external decode_int : 'rgb pixel_format -> array_frame -> (int, 'format) image option = "jpeg_decode"
