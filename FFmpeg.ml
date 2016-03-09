type context
type pts = Int64.t
type width = int
type height = int
type frame
type 'format bitmap = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

external demo : unit -> int = "ffmpeg_demo"

external open_ : string -> width -> height -> context = "ffmpeg_open"
    
external new_frame : context -> pts -> frame = "ffmpeg_frame_new"

external frame_buffer : frame -> 'format bitmap = "ffmpeg_frame_buffer"
  
external free_frame : frame -> unit = "ffmpeg_frame_free"

external write : context -> frame -> unit = "ffmpeg_write"

external close : context -> unit = "ffmpeg_close"

