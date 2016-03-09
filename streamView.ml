open Batteries
open Common

let fillbox frame_buf width x0 y0 x1 y1 color =
  for y = y0 to y1 do
    for x = x0 to x1 do
      frame_buf.{y * width + x} <- color
    done
  done

let seconds_from_midnight now =
  let tm = Unix.localtime now in
  float (tm.Unix.tm_hour * 3600 +
           tm.Unix.tm_min * 60 +
           tm.Unix.tm_sec) +. fst (modf now)


let reorder array =
  let c = ref 0 in
  let size = Bigarray.Array1.dim array - 1 in
  while !c < size do
    let r = array.{!c + 0} in
    (* (\* let g = array.{!c + 1} in *\) *)
    let b = array.{!c + 2} in

    array.{!c + 0} <- b;
      (* (\* array.{!c + 1} <- g; *\) *)
    array.{!c + 2} <- r;

    c := !c + 4
  done

module Save =
struct
  type context = {
    ffmpeg : FFmpeg.context;
    width  : int;
    height : int;
  }

  type t = {
    mutable context : context option;
    mutable prev_frame_time : float option;
    make_filename : float -> string;
  }

  let start make_filename =
    { context = None;
      make_filename;
      prev_frame_time = None }

  let save t (image, width, height) =
    let now = Unix.gettimeofday () in
    let frame_time = seconds_from_midnight @@ now in
    let ctx = match t.context with
      | None ->
         let ctx = {
           ffmpeg = FFmpeg.open_ (t.make_filename now) width height;
           width; height;
         } in
         t.context <- Some ctx;
         ctx
      | Some ctx when Some frame_time < t.prev_frame_time || ctx.width != width || ctx.height != ctx.height ->
         FFmpeg.close ctx.ffmpeg;
         let ctx = { ctx with ffmpeg = FFmpeg.open_ (t.make_filename now) ctx.width height } in
         t.context <- Some ctx;
         ctx
      | Some ctx -> ctx
    in
    t.prev_frame_time <- Some frame_time;
    let frame = FFmpeg.new_frame ctx.ffmpeg Int64.(of_float (frame_time *. 10000.0)) in
    let frame_buf = FFmpeg.frame_buffer frame in

    for y = 0 to height - 1 do
      let src = ref (4 * (y * width)) in
      let dst = ref (y * ctx.width) in
      for x = 0 to width - 1 do
        let r = image.{!src + 0} in
        let g = image.{!src + 1} in
        let b = image.{!src + 2} in
        frame_buf.{!dst} <- Int32.(logor
                                     (shift_left (of_int r) 16)
                                     (logor
                                        (shift_left (of_int g) 8)
                                        (of_int b)));
        dst := !dst + 1;
        src := !src + 4;
      done;
    done;
    FFmpeg.write ctx.ffmpeg frame;
    FFmpeg.free_frame frame

  let stop t =
    match t.context with
    | None -> ()
    | Some ctx -> FFmpeg.close ctx.ffmpeg
end

let make_filename config source now =
  let rec find_available number =
    let directory = Printf.sprintf "%s/%s" config.config_output_base source.source_name in
    Utils.mkdir_rec directory;
    let filename = Printf.sprintf "%s/%s-%04d.mp4" directory (Common.string_of_date (Unix.localtime now)) number in
    if Sys.file_exists filename then
      find_available (number + 1)
    else
      filename
  in
  find_available 0

let view ?packing config source http_mt () =
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
            save_images := None
        )
      | None ->
         "Save on", (
           fun () ->
             save_images := Some (Save.start (make_filename config source))
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
    show_exn @@ fun () ->
      match Jpeg.decode_int Jpeg.rgb4 (Jpeg.array_of_string data.data_content) with
      | Some jpeg_image ->
	 let (width, height) = (jpeg_image.Jpeg.image_width, jpeg_image.Jpeg.image_height) in
	 let rgb_data = jpeg_image.Jpeg.image_data in
         (match !save_images with
         | None -> ()
         | Some save -> Save.save save (rgb_data, width, height));
         let _ = reorder rgb_data in
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

