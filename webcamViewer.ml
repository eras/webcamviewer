open Batteries

let (@@) a b = a b

let destroy () =
  GMain.Main.quit ()

type source = {
  source_name : string;
  source_url  : string;
}

type config = {
  config_sources : source list;
  config_output_base : string;
}

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

let trim_crnl str =
  if String.length str >= 2
  then String.sub str 0 (String.length str - 2)
  else str

let pi2 = 8. *. atan 1.

let show_exn f =
  try 
    f ()
  with exn ->
    Printf.printf "Exception: %s (%s)\n%!" (Printexc.to_string exn) (Printexc.get_backtrace ());
    raise exn

let path_of_tm { Unix.tm_sec = sec;
                   tm_min = min;
                   tm_hour = hour;
                   tm_mday = mday;
                   tm_mon = mon;
                   tm_year = year } =
  Printf.sprintf
    "%04d-%02d-%02d/%02d"
    (year + 1900)
    (mon + 1)
    (mday)
    (hour)

let string_of_tm { Unix.tm_sec = sec;
                   tm_min = min;
                   tm_hour = hour;
                   tm_mday = mday;
                   tm_mon = mon;
                   tm_year = year } =
  Printf.sprintf
    "%04d-%02d-%02d %02d:%02d:%02d"
    (year + 1900)
    (mon + 1)
    (mday)
    (hour)
    (min)
    (sec)

let string_of_time t =
  string_of_tm (Unix.localtime t)

let frac x = fst (modf x)

let string_of_time_us t =
  string_of_tm (Unix.localtime t) ^ Printf.sprintf ".%06d" (int_of_float (frac t *. 1000000.0))

let path_of_time t = path_of_tm (Unix.localtime t)

let button_number ev =
  match GdkEvent.get_type ev, GdkEvent.unsafe_cast ev with
  | `BUTTON_PRESS, ev ->
     Some (GdkEvent.Button.button ev)
  | _ -> 
     None

let when_button n f ev =
  if button_number ev = Some n then
    f ev
  else
    false

let image_view ?packing () =
  let drawing_area = GMisc.drawing_area ?packing ~width:640 ~height:480 () in
  let image = ref None in
  let draw cr width height =
    let open Cairo in
    let r = 0.25 *. width in
    set_source_rgba cr 0. 1. 0. 0.5;
    match !image with
    | None -> 
      arc cr (0.5 *. width) (0.35 *. height) r 0. pi2;
      fill cr;
    (* set_source_rgba cr 1. 0. 0. 0.5; *)
      arc cr (0.35 *. width) (0.65 *. height) r 0. pi2;
      fill cr;
    (* set_source_rgba cr 0. 0. 1. 0.5; *)
      arc cr (0.65 *. width) (0.65 *. height) r 0. pi2;
      fill cr
    | Some (image, image_width, image_height) ->
      let (im_width, im_height) = (float image_width, float image_height) in
      let aspect = im_width /. im_height in
      let x_scale, y_scale =
	if width /. height > aspect 
	then (height /. im_height, height /. im_height)
	else (width /. im_width, width /. im_width)
      in
      translate
        cr
        (width /. 2.0 -. x_scale *. im_width /. 2.0)
        (height /. 2.0 -. y_scale *. im_height /. 2.0);
      scale cr x_scale y_scale;
      set_source_surface cr image ~x:0.0 ~y:0.0;
      rectangle cr 0.0 0.0 im_width im_height;
      fill cr
  in
  let expose ev =
    show_exn @@ fun () ->
      let open Cairo in
      let cr = Cairo_gtk.create drawing_area#misc#window in
      let allocation = drawing_area#misc#allocation in
      draw cr (float allocation.Gtk.width) (float allocation.Gtk.height);
      true
  in
  (* drawing_area#event#connect#expose ~callback:expose; *)
  ignore (drawing_area#event#connect#expose expose);
  drawing_area#event#add [`EXPOSURE];
  let interface =
    object
      method set_image image' =
        image := image';
        drawing_area#misc#draw None
    end
  in
  (drawing_area, interface)

let view ?packing config source http_mt () =
  let url = source.source_url in
  let save_images = ref false in
  let (drawing_area, interface) = image_view ?packing () in
  let fullscreen = ref None in
  let popup_menu_button_press ev =
    let menu = GMenu.menu () in
    let (label, action) = 
      if !save_images then
        "Save off", (fun () -> save_images := false)
      else 
        "Save on", (fun () -> save_images := true)
    in
    let menuItem = GMenu.menu_item ~label:label ~packing:menu#append () in
    ignore (menuItem#connect#activate ~callback:action);
    menu#popup ~button:3 ~time:(GdkEvent.get_time ev);
    true
  in
  let fullscreen_window _ev =
    let fullscreen_close ev =
      match !fullscreen with
      | None -> false
      | Some (window, _) ->
         window#destroy ();
         fullscreen := None;
         true
    in
    ( match !fullscreen with
      | None ->
         let w = GWindow.window () in
         w#show ();
         w#maximize ();
         let (drawing_area, interface) = image_view ~packing:w#add () in
         fullscreen := Some (w, (drawing_area, interface));
         
         drawing_area#event#add [`BUTTON_PRESS];
         ignore (drawing_area#event#connect#button_press fullscreen_close);
         ignore (w#event#connect#delete fullscreen_close);
      | Some _ ->
         () );
    true
  in
  ignore (drawing_area#event#connect#button_press (when_button 3 popup_menu_button_press));
  ignore (drawing_area#event#connect#button_press (when_button 1 fullscreen_window));
  drawing_area#event#add [`BUTTON_PRESS];
  let http = Curl.init () in
  let header = ref [] in
  Curl.set_url http url;
  let boundary_decoder = ref (fun _ -> assert false) in
  Curl.set_writefunction http (fun str ->
    (* Printf.printf "%d bytes\n%!" (String.length str) (\* str *\); *)
    let decoder = BoundaryDecoder.feed_decoder (!boundary_decoder ()) str 0 (String.length str) in
    boundary_decoder := (fun () -> decoder);
    String.length str
  );
  let received_data (data : BoundaryDecoder.data) =
    show_exn @@ fun () ->
      let content_length = int_of_string (List.assoc "Content-Length" data.data_header) in
      (* Printf.printf "Received data (%d/%d bytes)\n%!" (String.length data.data_content) content_length; *)
      if !save_images then (
        let now = Unix.gettimeofday () in
        let directory = Printf.sprintf "%s/%s/%s" config.config_output_base source.source_name (path_of_time now) in
        Utils.mkdir_rec directory;
	let filename = Printf.sprintf "%s/%s.jpg" directory (string_of_time_us now) in
	output_file ~filename ~text:data.data_content;
      );
      match Jpeg.decode_int Jpeg.rgb4 (Jpeg.array_of_string data.data_content) with
      | Some jpeg_image ->
	let (width, height) = (jpeg_image.Jpeg.image_width, jpeg_image.Jpeg.image_height) in
	let rgb_data = jpeg_image.Jpeg.image_data in
        let image = Some (Cairo.Image.create_for_data8 rgb_data Cairo.Image.RGB24 width height, width, height) in
        interface#set_image image;
        Option.may (fun (_, (_, interface)) -> interface#set_image image) !fullscreen;
      | None ->
	()
  in
  let header_finished header =
    let boundary = 
      let contenttype = List.assoc "Content-Type" header in
      match Pcre.extract ~full_match:false ~pat:"^multipart/x-mixed-replace; *boundary=(?:--)?(.*)" contenttype with
      | [|boundary|] -> 
	boundary
      | _ -> failwith (Printf.sprintf "Failed to find expected Content-Type -header (%s)" contenttype)
    in
    let decoder = BoundaryDecoder.decode_boundaries boundary received_data in
    boundary_decoder := (fun () -> decoder);
    ()
  in
  let receive_header = ref (fun _ -> assert false) in
  let rec receive_http_header str =
      let (code, message) = Utils.split_http_header str in
      (* Printf.printf "HTTP: %d %s\n%!" code message; *)
      receive_header := receive_kv;
  and receive_kv str =
    if str = ""
    then header_finished (List.rev !header) (* Done *)
    else header := Utils.split_key_value str::!header;
  in
  receive_header := receive_http_header;
  Curl.set_headerfunction http (fun str ->
    show_exn @@ fun () ->
      let trimmed_str = trim_crnl str in
      (* Printf.printf "Processing header: %d %s\n%!" (String.length trimmed_str) trimmed_str; *)
      !receive_header trimmed_str;
      String.length str
  );
  Curl.Multi.add http_mt http;
  drawing_area

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
  List.iter (fun source -> ignore (view config source http_mt ~packing:vbox#add ())) config.config_sources;
  main_window#show ();
  GMain.Main.main ()

let _ = main ()
