open Batteries
open Ffmpeg

let main' () =
  demo ()

let main () =
  init ();
  let ctx = open_ "foo.mp4" 640 480 in
  let _ = List.(0 -- 200) |> Enum.iter (
    fun n ->
      let frame = new_frame ctx Int64.(of_int n * 100L) in
      let frame_buf = frame_buffer frame in
      let width = 640 in
      let fillbox x0 y0 x1 y1 color =
        for y = y0 to y1 do
          for x = x0 to x1 do
            frame_buf.{y * width + x} <- color
          done
        done
      in
      fillbox 0 0 (640 - 1) (480 - 1) 0l;
      fillbox (n + 100) (100) (n + 200) (200) 0xffffffl;
      write ctx frame;
      free_frame frame;
      ()
  ) in
  close ctx;
  ()

let _ = main ()
