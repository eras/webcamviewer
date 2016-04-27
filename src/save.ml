open Batteries
open Common
    
type context = {
  ffmpeg : [`Write] FFmpeg.context;
  stream : ([`Video], [`Write]) FFmpeg.stream;
  width  : int;
  height : int;
}

type t = {
  mutable context : context option;
  mutable prev_frame_time : float option;
  make_filename : float -> string;
  frame_time : float -> float;
}

let start ~make_filename ~frame_time =
  { context = None;
    make_filename;
    prev_frame_time = None;
    frame_time = frame_time }

let save t time (image, width, height) =
  let frame_time = t.frame_time @@ time in
  let ctx = match t.context with
    | None ->
      let ffmpeg = FFmpeg.create (t.make_filename time) in
      let stream = FFmpeg.new_stream ffmpeg FFmpeg.(CreateVideo { v_width = width; v_height = height }) in
      let () = FFmpeg.open_ ffmpeg in
      let ctx = {ffmpeg; stream; width; height;} in
      t.context <- Some ctx;
      ctx
    | Some ctx when Some frame_time < t.prev_frame_time || ctx.width != width || ctx.height != ctx.height ->
      FFmpeg.close_stream ctx.stream;
      FFmpeg.close ctx.ffmpeg;
      let ffmpeg = FFmpeg.create (t.make_filename time) in
      let stream = FFmpeg.new_stream ffmpeg FFmpeg.(CreateVideo { v_width = width; v_height = height }) in
      let () = FFmpeg.open_ ffmpeg in
      let ctx = { ctx with ffmpeg; stream } in
      t.context <- Some ctx;
      ctx
    | Some ctx -> ctx
  in
  t.prev_frame_time <- Some frame_time;
  let frame = FFmpeg.new_frame ctx.stream frame_time in
  let frame_buf = FFmpeg.frame_buffer frame in

  let image : (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t = Utils.convert_bigarray1 image in
  let module LE = EndianBigstring.LittleEndian_unsafe in
  for y = 0 to height - 1 do
    let src = ref (4 * (y * width)) in
    let dst = ref (y * ctx.width) in
    for x = 0 to width - 1 do
      frame_buf.{!dst} <- LE.get_int32 image !src;
      dst := !dst + 1;
      src := !src + 4;
    done;
  done;
  FFmpeg.write ctx.stream frame;
  FFmpeg.free_frame frame

let stop t =
  match t.context with
  | None -> ()
  | Some ctx ->
    let try' f arg =
      try f arg
      with exn ->
        Printf.fprintf stderr "Exception %s while closing stream.\n%s\n%!"
          (Printexc.to_string exn)
          (Printexc.get_backtrace ())
    in
    try' FFmpeg.close_stream ctx.stream;
    try' FFmpeg.close ctx.ffmpeg
