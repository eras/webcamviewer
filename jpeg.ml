type array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type rgb_array_frame = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

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

external decode : array_frame -> rgb_array_frame = "jpeg_decode"
