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

let ctypes = Findlib.query "ctypes"

let ffmpeg_packages = "libavformat,libavutil,libavcodec,libswscale,libswresample"
let ffmpeg_flags = lazy (pkg_config "cflags" ffmpeg_packages)
let ffmpeg_libs = lazy (pkg_config "libs" ffmpeg_packages)

let ccoptify flags = flags |> List.map (fun x -> [A"-ccopt"; x]) |> List.concat

let ctypes_rules cbase phase1gen phase2gen ocaml =
  rule "ctypes generated c"
    ~dep:phase1gen
    ~prod:(cbase ^ ".c")
    (fun _ _ ->
       Cmd(S[P ("./" ^ phase1gen); Sh">"; A(cbase ^ ".c")]));

  rule "ctypes generated exe"
    ~dep:(cbase ^ ".o")
    ~prod:phase2gen
    (fun _ _ ->
       Cmd (S ([Sh "cc"; A(cbase ^ ".o");
                A"-o"; A phase2gen;
                A"-I"; A ctypes.Findlib.location] @ Lazy.force ffmpeg_libs))
    );

  rule "ctypes generated ml"
    ~dep:phase2gen
    ~prod:ocaml
    (fun _ _ ->
       Cmd(S[P ("./" ^ phase2gen); Sh">"; A ocaml]))

let setup_ffmpeg () =
  ocaml_lib "ffmpeg/libFFmpeg";

  flag ["mktop"; "use_libFFmpeg"] (A"-custom");
  dep ["link"; "use_libFFmpeg"; "byte"] ["ffmpeg/libFFmpeg.cma"];
  dep ["link"; "use_libFFmpeg"; "native"] ["ffmpeg/libFFmpeg.cmxa"];

  flag ["c"; "compile"; "build_FFmpeg"] (S (ccoptify @@ Lazy.force ffmpeg_flags));
  flag ["c"; "compile"; "build_FFmpeg"] (S [A "-ccopt"; A "-O0"]);
  flag ["c"; "compile"; "build_FFmpeg"] (S [A "-ccopt"; A "-W"]);
  flag ["c"; "compile"; "build_FFmpeg"] (S [A "-ccopt"; A "-Wall"]);
  flag ["c"; "compile"; "build_FFmpeg"] (S [A "-ccopt"; A "-Wno-missing-field-initializers"]);
  flag ["link"; "library"; "ocaml"; "build_FFmpeg"] (S[
      S (ccoptify @@ Lazy.force ffmpeg_libs);
      S [A "-cclib"; A "-Lffmpeg"; A "-cclib"; A"-lFFmpeg-stubs"]
    ]
    );
  dep ["link"; "build_FFmpeg"] ["ffmpeg/libFFmpeg-stubs.a"];

  ctypes_rules "ffmpeg/FFmpegGenGen-c" "ffmpeg/FFmpegGen.byte" "ffmpeg/FFmpegGenGen" "ffmpeg/FFmpegGeneratedCTypes.ml"

let _ = dispatch begin function
  | Before_options ->
    Options.use_ocamlfind := true
  | After_rules ->
    setup_ffmpeg ();

    flag ["ocaml"; "compile"; "no_warn_40"] (S[A"-w"; A"-40"]);
    flag ["c"; "compile"; "use_libjpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DLIBJPEG=1"]);
    flag ["c"; "compile"; "use_turbojpeg"] (S[A"-ccopt"; A"-g"; A"-ccopt"; A"-DTURBOJPEG=1"]);
    flag ["ocaml"; "link"; "use_libjpeg"; "native"] (S[A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
    flag ["ocaml"; "link"; "use_libjpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -ljpeg -Wall -W -Wno-unused-parameter"]);
    flag ["ocaml"; "link"; "use_turbojpeg"; "native"] (S[A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
    flag ["ocaml"; "link"; "use_turbojpeg"; "byte"] (S[A"-custom"; A"-ccopt"; A"-g -lturbojpeg -Wall -W -Wno-unused-parameter"]);
    flag ["ocaml"; "link"; "use_turbojpeg"; "byte"] (S[A"-custom"]);
    dep ["link"; "ocaml"; "use_libjpeg"] ["src/jpeg-c.o"];
    dep ["link"; "ocaml"; "use_turbojpeg"] ["src/jpeg-c.o"];

    flag ["c"; "compile"; "use_ctypes"] (S[A"-ccopt"; A"-I"; A"-ccopt"; A ctypes.Findlib.location]);

  | _ -> ()
end
