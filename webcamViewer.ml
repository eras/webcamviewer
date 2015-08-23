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

let make_http_mt () =
  let http_mt = Curl.Multi.create () in
  let http_mt_fds = Hashtbl.create 10 in
  let io_callback fd conds =
    let fd_status =
      let open Curl.Multi in
      match conds with
      | [`IN]			  -> EV_IN
      | [`OUT]			  -> EV_OUT
      | [`IN; `OUT] | [`OUT; `IN] -> EV_INOUT
      | _			  -> EV_AUTO
    in
    ignore (Curl.Multi.action http_mt fd fd_status);
    true
  in
  Curl.Multi.set_socket_function http_mt (
    fun fd poll ->
      let gtk_cond_of_curl_poll = 
	let open Curl.Multi in function
	  | POLL_NONE | POLL_REMOVE -> []
	  | POLL_IN		    -> [`IN]
	  | POLL_OUT		    -> [`OUT]
	  | POLL_INOUT		    -> [`IN; `OUT]
      in
      if Hashtbl.mem http_mt_fds fd then
	GMain.Io.remove (Hashtbl.find http_mt_fds fd);
      Hashtbl.remove http_mt_fds fd;
      match gtk_cond_of_curl_poll poll with
      | [] -> (* OK, we're done here *) ()
      | cond ->
	let id =
	  GMain.Io.add_watch
	    ~cond
	    ~callback:(io_callback fd)
	    (GMain.Io.channel_of_descr fd)
	in
	Hashtbl.add http_mt_fds fd id
  );
  let timeout_id = ref None in
  let timer_callback () =
    Curl.Multi.action_timeout http_mt;
    timeout_id := None;
    false
  in
  Curl.Multi.set_timer_function http_mt (
    fun ms ->
      if ms >= 0 then
	timeout_id := Some (GMain.Timeout.add ~ms ~callback:timer_callback);
  );
  http_mt

let main () =
  let http_mt = make_http_mt () in
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
