open OUnit2

module F = FFmpeg

let create test_ctx =
  ignore (F.create "test.mp4");
  ()

let create_close test_ctx =
  let f = F.create "test.mp4" in
  F.close f;
  ()

let ffmpeg =
  "FFmpeg" >:::
  ["create" >:: create;
   "create_close" >:: create_close;
  ]

let _ =
  run_test_tt_main ffmpeg
    
