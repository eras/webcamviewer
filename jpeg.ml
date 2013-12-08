type array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type 'a rgb_array_frame = ('a, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type 'a image = {
  image_width : int;
  image_height : int;
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
      set ar c (String.get str c)
    done;
    ar

external decode_char : array_frame -> char image = "jpeg_decode"
external decode_int : array_frame -> int image = "jpeg_decode"
