type t

(** [start make_filename] starts saving. make_filename returns the
    file name to be used for a given unix epoch time. *)
val start : make_filename : (float -> string) -> frame_time : (float -> float) -> t

(** [save t (Unix.gettimeofday ()) (image, width, height) Saves an 0x00rrggbb image to the stream *)
val save :
  t ->
  float ->
  (int, 'a, 'b) Batteries.Bigarray.Array1.t * FFmpeg.width * FFmpeg.height ->
  unit

(** [stop t] stops saving the video *)
val stop : t -> unit
