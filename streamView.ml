open Batteries
open Common

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
    HttpChunkStream.start ~on_eof http_mt url (received_data config source interface)
  in
  start ();
  drawing_area

