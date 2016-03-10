open Batteries
open Common
    
type context = {
  ffmpeg : FFmpeg.context;
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

let save t (image, width, height) =
  let now = Unix.gettimeofday () in
  let frame_time = t.frame_time @@ now in
  let ctx = match t.context with
    | None ->
      let ctx = {
        ffmpeg = FFmpeg.open_ (t.make_filename now) width height;
        width; height;
      } in
      t.context <- Some ctx;
      ctx
    | Some ctx when Some frame_time < t.prev_frame_time || ctx.width != width || ctx.height != ctx.height ->
      FFmpeg.close ctx.ffmpeg;
      let ctx = { ctx with ffmpeg = FFmpeg.open_ (t.make_filename now) ctx.width height } in
      t.context <- Some ctx;
      ctx
    | Some ctx -> ctx
  in
  t.prev_frame_time <- Some frame_time;
  let frame = FFmpeg.new_frame ctx.ffmpeg frame_time in
  let frame_buf = FFmpeg.frame_buffer frame in

  for y = 0 to height - 1 do
    let src = ref (4 * (y * width)) in
    let dst = ref (y * ctx.width) in
    for x = 0 to width - 1 do
      let r = image.{!src + 0} in
      let g = image.{!src + 1} in
      let b = image.{!src + 2} in
      frame_buf.{!dst} <- Int32.(logor
                                   (shift_left (of_int r) 16)
                                   (logor
                                      (shift_left (of_int g) 8)
                                      (of_int b)));
      dst := !dst + 1;
      src := !src + 4;
    done;
  done;
  FFmpeg.write ctx.ffmpeg frame;
  FFmpeg.free_frame frame

let stop t =
  match t.context with
  | None -> ()
  | Some ctx -> FFmpeg.close ctx.ffmpeg
