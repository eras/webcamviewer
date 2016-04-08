include FFmpegTypes

let _ = Callback.register_exception "FFmpeg exception" (Exception (ContextAlloc, 0))

module FFmpegCTypes = FFmpegBindings.Types(FFmpegGeneratedCTypes)

let _ = FFmpegCTypes.avmedia_type_to_c AVMEDIA_TYPE_VIDEO

let _ = Printexc.register_printer @@ fun exn ->
  match exn with
  | Exception (kind, code) ->
    let kind_str = match kind with
      | ContextAlloc -> "ContextAlloc"
      | Open -> "Open"
      | FileIO -> "FileIO"
      | StreamInfo -> "StreamInfo"
      | WriteHeader -> "WriteHeader"
      | Memory -> "Memory"
      | Logic -> "Logic"
      | Encode -> "Encode"
      | Closed -> "Closed"
    in
    Some (Printf.sprintf "FFmpeg.Exception (%s, %d)" kind_str code)
  | _ -> None

external create_ : string -> [`Write] context = "ffmpeg_create"

(* Wrapper ensuring the file gets evaluated if the functionality is used *)
let create x = create_ x

external open_input_ : string -> [`Read] context = "ffmpeg_open_input"

(* Wrapper ensuring the file gets evaluated if the functionality is used *)
let open_input x = open_input_ x

external new_stream : [`Write] context -> 'media_info media_new_info -> ('media_info, [<`Write]) stream = "ffmpeg_stream_new"

(* external open_stream : [`Read] context -> index -> 'media_info media_type -> ('media_info, [<`Write]) stream = "ffmpeg_stream_open" *)

external open_ : 'rw context -> unit = "ffmpeg_open"

external new_frame : ('media_info, [`Write]) stream -> pts -> 'media_info frame = "ffmpeg_frame_new"

external frame_buffer : [>`Video] frame -> 'format bitmap = "ffmpeg_frame_buffer"
  
external free_frame : 'media_info frame -> unit = "ffmpeg_frame_free"

external write : ('media_info, 'rw) stream -> 'media_info frame -> unit = "ffmpeg_write"

external close_stream : ('media_info, 'rw) stream -> unit = "ffmpeg_stream_close"

external close : 'rw context -> unit = "ffmpeg_close"
