open Ocamlbuild_plugin
open Command

let _ = dispatch begin function
  | After_rules ->
      flag ["ocaml"; "compile"; "no_warn_40"] (S[A"-w"; A"-40"]);

      flag ["c"; "compile"; "use_libjpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DLIBJPEG=1"]);
      flag ["c"; "compile"; "use_turbojpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DTURBOJPEG=1"]);
      flag ["ocaml"; "link"; "use_libjpeg"; "native"] (S[A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
      flag ["ocaml"; "link"; "use_libjpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
      flag ["ocaml"; "link"; "use_turbojpeg"; "native"] (S[A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
      flag ["ocaml"; "link"; "use_turbojpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
      dep ["link"; "ocaml"; "use_libjpeg"] ["jpeg-c.o"];
      dep ["link"; "ocaml"; "use_turbojpeg"] ["jpeg-c.o"]
  | _ -> ()
end
