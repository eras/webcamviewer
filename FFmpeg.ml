type context
type pts = float
type width = int
type height = int
type 'media_kind frame
type video = {
  v_width  : int;
  v_height : int;
}
type audio = {
  a_samplerate : int;
  a_channels   : int;
  a_layout     : int option;
}
type data
type 'a media_kind =
  | Video : video -> [`Video] media_kind
  | Audio : audio -> [`Audio] media_kind
  | Data  : data  -> [`Data]  media_kind
type 'media_kind stream
type 'format bitmap = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

external demo : unit -> int = "ffmpeg_demo"

external create : string -> context = "ffmpeg_create"

external new_stream : context -> 'media_kind media_kind -> 'media_kind stream = "ffmpeg_stream_new"

external open_ : context -> unit = "ffmpeg_open"

external new_frame : 'media_kind stream -> pts -> 'media_kind frame = "ffmpeg_frame_new"

external frame_buffer : [>`Video] frame -> 'format bitmap = "ffmpeg_frame_buffer"
  
external free_frame : 'media_kind frame -> unit = "ffmpeg_frame_free"

external write : 'media_kind stream -> 'media_kind frame -> unit = "ffmpeg_write"

external close_stream : 'media_kind stream -> unit = "ffmpeg_stream_close"

external close : context -> unit = "ffmpeg_close"

