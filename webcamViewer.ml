open Batteries
open Common

let destroy () =
  GMain.Main.quit ()

(* let read_config_file () = *)
(*   let open Config_file in *)
(*   let config_file = create_options_file (Unix.getenv "HOME" ^ "/.webcamviewer2") in *)
(*   let streams = new group  *)

let read_config_file () =
  let open Toml in
  let config_file = Unix.getenv "HOME" ^ "/.webcamviewer" in
  let general, cameras = List.partition (fun (name, _) -> name = "general") @@ tables_to_list (from_filename config_file) in
  let sources =
    cameras |> List.map @@ fun (name, camera_config) ->
      { source_url = get_string camera_config "url";
        source_name = name; } in
  let default_general_option key default =
    match general with
    | [] -> default
    | (_, general)::_ ->
      try get_string general key
      with Not_found -> default
  in
  let config = {
    config_sources = sources;
    config_output_base = default_general_option "output" "output";
  } in
  config

(* let read_streams () = File.lines_of (Unix.getenv "HOME" ^ "/.webcamviewer") |> List.of_enum *)

let main () =
  let http_mt = GtkCurlLoop.make () in
  let main_window = GWindow.window ~border_width:10 () in
  Gobject.set GtkBaseProps.Window.P.allow_shrink main_window#as_window true;
  ignore (main_window#connect#destroy ~callback:destroy);
  let vbox = GPack.vbox ~packing:main_window#add () in
  let quit_button = GButton.button ~label:"Quit" ~packing:(vbox#pack ~expand:false) () in
  ignore (quit_button#connect#clicked ~callback:destroy);
  let config = read_config_file () in
  List.iter (fun source -> ignore (StreamView.view config source http_mt ~packing:vbox#add ())) config.config_sources;
  main_window#show ();
  GMain.Main.main ()

let _ = main ()
