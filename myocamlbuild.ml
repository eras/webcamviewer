open Ocamlbuild_plugin
open Command

let _ = dispatch begin function
  | After_rules ->
      flag ["ocaml"; "compile"; "no_warn_40"] (S[A"-w"; A"-40"]);

      flag ["c"; "compile"] (S[A"-ccopt"; A"-g"]);
      flag ["ocaml"; "link"; "use_jpeg"; "native"] (S[A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
      flag ["ocaml"; "link"; "use_jpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
      dep ["link"; "ocaml"; "use_jpeg"] ["jpeg-c.o"]
  | _ -> ()
end
