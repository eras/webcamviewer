open Ctypes

let main () =
  Format.fprintf Format.std_formatter "#include <libavutil/avutil.h>\n";
  Cstubs_structs.write_c Format.std_formatter (module FFmpegBindings.Types)

let _ = main ()
