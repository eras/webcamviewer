open Batteries
open Common

let reorder array =
  let c = ref 0 in
  let module A = Bigarray.Array1 in
  let size = A.dim array - 1 in
  while !c < size - 3 do
    let r = A.unsafe_get array (!c + 0) in
    (* (\* let g = array.{!c + 1} in *\) *)
    let b = A.unsafe_get array (!c + 2) in

    A.unsafe_set array (!c + 0) b;
      (* (\* array.{!c + 1} <- g; *\) *)
    A.unsafe_set array (!c + 2) r;

    c := !c + 4
  done

let make_filename config source now =
  let rec find_available number =
    let directory = Printf.sprintf "%s/%s" config.config_output_base source.source_name in
    Utils.mkdir_rec directory;
    let time_str =
      let tm = Unix.localtime now in
      Printf.sprintf
        "%04d-%02d-%02d_%02d-%02d"
        (tm.tm_year + 1900)
        (tm.tm_mon + 1)
        (tm.tm_mday)
        (tm.tm_hour)
        tm.tm_min
    in
    let filename = Printf.sprintf "%s/%s__%04d.mp4" directory time_str number in
    if Sys.file_exists filename then
      find_available (number + 1)
    else
      filename
  in
  find_available 0

let seconds_from_midnight now =
  let tm = Unix.localtime now in
  float (tm.Unix.tm_hour * 3600 +
           tm.Unix.tm_min * 60 +
           tm.Unix.tm_sec) +. fst (modf now)

let seconds_from_hour now =
  let tm = Unix.localtime now in
  float (tm.Unix.tm_min * 60 +
         tm.Unix.tm_sec) +. fst (modf now)

let make_frame_time time =
  seconds_from_hour time

let saving_overlay cr image =
  match image with
  | None -> ()
  | Some (_, image_width, image_height) ->
    let (im_width, im_height) = (float image_width, float image_height) in
    let open Cairo in
    set_source_rgb cr ~r:1.0 ~g:0.0 ~b:0.0;
    arc cr (im_width -. 10.0) (10.0) 5.0 0. pi2;
    fill cr

let view ~work_queue ?packing config source http_mt () =
  let worker = SingleWorker.create work_queue in
  let url = source.source_url in
  let save_images = ref None in
  let (drawing_area, interface) = ImageView.view ?packing () in
  let fullscreen = ref None in
  let popup_menu_button_press ev =
    let menu = GMenu.menu () in
    let (label, action) =
      match !save_images with
      | Some save ->
        "Save off", (
          fun () ->
            Save.stop save;
            interface#set_overlay (fun _ _ -> ());
            save_images := None
        )
      | None ->
         "Save on", (
           fun () ->
             interface#set_overlay saving_overlay;
             save_images := Some (Save.start (make_filename config source) make_frame_time)
         )
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
    SingleWorker.submit worker @@ fun () ->
    show_exn @@ fun () ->
    match Jpeg.decode_int Jpeg.rgb4 (Jpeg.array_of_string data.data_content) with
    | Some jpeg_image ->
      let (width, height) = (jpeg_image.Jpeg.image_width, jpeg_image.Jpeg.image_height) in
      let rgb_data = jpeg_image.Jpeg.image_data in
      (match !save_images with
       | None -> ()
       | Some save ->
         if WorkQueue.queue_length work_queue < 20 then
           WorkQueue.async work_queue @@ fun () ->
           Save.save save (rgb_data, width, height)
         else
           Printf.eprintf "Warning: too much pending work, skipping frames\n%!"
      );
      (* let _ = reorder rgb_data in *)
      let image = Some (Cairo.Image.create_for_data8 rgb_data Cairo.Image.RGB24 width height, width, height) in
      GtkThread.async (fun () ->
          interface#set_image image;
          Option.may (fun (_, (_, interface)) -> interface#set_image image) !fullscreen)
        ()
    | None ->
      ()
  in
  let http_control = ref None in
  let rec start () =
    let on_eof () = start () in
    http_control := Some (HttpChunkStream.start ~on_eof http_mt url (received_data config source interface))
  in
  start ();
  object
    method drawing_area = drawing_area
    method finish callback =
      ( match !save_images with
        | None -> ()
        | Some save ->
          Printf.printf "Stopping save%!\n";
          Save.stop save;
          save_images := None );
      match !http_control with
      | None -> callback ()
      | Some http_control -> http_control#finish callback
  end
