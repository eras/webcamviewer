open Batteries
open Common

let destroy () =
  GMain.Main.quit ()

(* let read_config_file () = *)
(*   let open Config_file in *)
(*   let config_file = create_options_file (Unix.getenv "HOME" ^ "/.webcamviewer2") in *)
(*   let streams = new group  *)

module List_of_Map (Map: Legacy.Map.S) =
struct
  let map m = Map.fold (fun (key : Map.key) value xs -> (key, value)::xs) m [] |> List.rev
end

let map_fst f xs = List.map (fun (k, v) -> (f k, v)) xs

let read_config_file () =
  let open Toml in
  let config_file = Unix.getenv "HOME" ^ "/.webcamviewer" in
  match Parser.from_filename config_file with
  | `Error (message, location) ->
     Printf.eprintf "Error while reading configuration: %s at line %d column %d\n"
       location.source
       location.line
       location.column;
    None
  | `Ok config ->
     let config = let module M = List_of_Map (TomlTypes.Table) in M.map config |> map_fst TomlTypes.Table.Key.to_string in
     let general, cameras = List.partition (fun (name, _) -> name = "general") @@ config in
     let sources =
       cameras |> List.map @@ fun (name, camera_config) ->
         { source_url = Option.get (TomlLenses.(get camera_config (table |-- key "url" |-- string)));
           source_name = name; } in
     let default_general_option key_ default =
       match general with
       | [] -> default
       | (_, general)::_ ->
          Option.default default @@ TomlLenses.(get general (table |-- key key_ |-- string))
     in
     let config = {
       config_sources = sources;
       config_output_base = default_general_option "output" "output";
     } in
     Some config

(* let read_streams () = File.lines_of (Unix.getenv "HOME" ^ "/.webcamviewer") |> List.of_enum *)

let main () =
  let http_mt = GtkCurlLoop.make () in
  let main_window = GWindow.window ~border_width:10 () in
  Gobject.set GtkBaseProps.Window.P.allow_shrink main_window#as_window true;
  ignore (main_window#connect#destroy ~callback:destroy);
  let vbox = GPack.vbox ~packing:main_window#add () in
  let quit_button = GButton.button ~label:"Quit" ~packing:(vbox#pack ~expand:false) () in
  ignore (quit_button#connect#clicked ~callback:destroy);
  match read_config_file () with
  | Some config ->
     List.iter (fun source -> ignore (StreamView.view config source http_mt ~packing:vbox#add ())) config.config_sources;
     main_window#show ();
     GMain.Main.main ()
  | None ->
     ()

let _ = main ()
