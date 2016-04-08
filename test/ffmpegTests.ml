open OUnit2

module F = FFmpeg

let create_close test_ctx =
  let f = F.create "create_close.mp4" in
  F.close f;
  ()

let new_stream test_ctx =
  let f = F.create "new_stream.mp4" in
  let s = F.new_stream f (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.close_stream s;
  F.close f;
  ()

let write_frame test_ctx =
  let f = F.create "write_frame.mp4" in
  let s = F.new_stream f (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.open_ f;
  let frame = F.new_frame s 0.0 in
  let _fb = F.frame_buffer frame in
  F.write s frame;
  F.free_frame frame;
  F.close_stream s;
  F.close f;
  ()

let write_frames test_ctx =
  let f = F.create "write_frames.mp4" in
  let s = F.new_stream f (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.open_ f;
  for i = 0 to 100 do
    let frame = F.new_frame s (float i /. 10.0) in
    let _fb = F.frame_buffer frame in
    F.write s frame;
    F.free_frame frame;
  done;
  F.close_stream s;
  F.close f;
  ()

let close_stream_twice test_ctx =
  let f = F.create "new_stream.mp4" in
  let s = F.new_stream f (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.close_stream s;
  assert_raises (FFmpeg.Exception (Closed, 0)) (fun () ->
      F.close_stream s;
    );
  F.close f;
  ()

let ffmpeg =
  "FFmpeg" >:::
  ["create_close"       >:: create_close;
   "new_stream"         >:: new_stream;
   "write_frame"        >:: write_frame;
   "write_frames"       >:: write_frames;
   "close_stream_twice" >:: close_stream_twice;
   ]

let _ =
  run_test_tt_main ffmpeg
    
