open Ocamlbuild_plugin
open Command

(* Copied from https://github.com/dbuenzli/tgls/blob/master/myocamlbuild.ml *)
let pkg_config flags package =
  let has_package =
    try ignore (run_and_read ("pkg-config --exists " ^ package)); true
    with Failure _ -> false
  in
  let cmd tmp =
    Command.execute ~quiet:true &
      Cmd( S [ A "pkg-config"; A ("--" ^ flags); A package; Sh ">"; A tmp]);
    List.map (fun arg -> A arg) (string_list_of_file tmp)
  in
  if has_package then with_temp_file "pkgconfig" "pkg-config" cmd else []

let _ = dispatch begin function
  | Before_options ->
     Options.use_ocamlfind := true
  | After_rules ->
     let ffmpeg_flags = pkg_config "cflags" "libavformat,libavutil,libavcodec,libswscale" in
     let ffmpeg_libs = pkg_config "libs" "libavformat,libavutil,libavcodec,libswscale" in
     let ccoptify flags = flags |> List.map (fun x -> [A"-ccopt"; x]) |> List.concat in
     flag ["ocaml"; "compile"; "no_warn_40"] (S[A"-w"; A"-40"]);
     flag ["c"; "compile"; "use_libjpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DLIBJPEG=1"]);
     flag ["c"; "compile"; "use_turbojpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DTURBOJPEG=1"]);
     flag ["c"; "compile"; "use_ffmpeg"] (S (ccoptify ffmpeg_flags));
     flag ["ocaml"; "link"; "use_libjpeg"; "native"] (S[A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
     flag ["ocaml"; "link"; "use_libjpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
     flag ["ocaml"; "link"; "use_turbojpeg"; "native"] (S[A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
     flag ["ocaml"; "link"; "use_turbojpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
     flag ["ocaml"; "link"; "use_turbojpeg"; "byte"] (S[A"-custom"]);
     flag ["ocaml"; "link"; "use_turbojpeg"] (S (ccoptify ffmpeg_libs));
     dep ["link"; "ocaml"; "use_libjpeg"] ["jpeg-c.o"];
     dep ["link"; "ocaml"; "use_turbojpeg"] ["jpeg-c.o"];
     dep ["link"; "ocaml"; "use_ffmpeg"] ["ffmpeg-c.o"];
  | _ -> ()
end
