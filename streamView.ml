open Batteries
open Common

let header_finished received_data boundary_decoder http header =
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

let start_http ~on_eof http_mt url process =
  let http = Curl.init () in
  let header = ref [] in
  Curl.set_url http url;
  let boundary_decoder = ref (fun _ -> assert false) in
  Curl.set_writefunction http (fun str ->
    if String.length str = 0 then (
      on_eof ();
      0
    ) else (
      try
        (* Printf.printf "%d bytes\n%!" (String.length str) (\* str *\); *)
        let decoder = BoundaryDecoder.feed_decoder (!boundary_decoder ()) str 0 (String.length str) in
        boundary_decoder := (fun () -> decoder);
        String.length str
      with exn ->
        Printf.fprintf stderr "StreamView: uncaught exception: %s\n%!" (Printexc.to_string exn);
        Printexc.print_backtrace stdout;
        0
    );
  );
  let receive_header = ref (fun _ -> assert false) in
  let rec receive_http_header str =
    let (code, message) = Utils.split_http_header str in
      (* Printf.printf "HTTP: %d %s\n%!" code message; *)
    receive_header := receive_kv;
  and receive_kv str =
    if str = ""
    then header_finished process boundary_decoder http (List.rev !header) (* Done *)
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
  Curl.Multi.add http_mt http

let view ?packing config source http_mt () =
  let url = source.source_url in
  let save_images = ref false in
  let (drawing_area, interface) = ImageView.view ?packing () in
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
         let (drawing_area, interface) = ImageView.view ~packing:w#add () in
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
  let received_data config source interface (data : BoundaryDecoder.data) =
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
  let rec start () =
    let on_eof () =
      start ()
    in
    start_http ~on_eof http_mt url (received_data config source interface)
  in
  start ();
  drawing_area

