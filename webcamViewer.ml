open Batteries

let (@@) a b = a b

let destroy () =
  GMain.Main.quit ()

type source = {
  source_url : string;
}

let save_images = false

let read_streams () = File.lines_of "streams" |> List.of_enum

let trim_crnl str =
  if String.length str >= 2
  then String.sub str 0 (String.length str - 2)
  else str

let pi2 = 8. *. atan 1.

let expand_rgb width height rgb =
  let open Bigarray in
  let open Array1 in
  let array = create (kind rgb) (layout rgb) (width * height * 4) in
  for c = 0 to width * height - 1 do
    set array (c * 4 + 0) (get rgb (c * 3 + 0));
    set array (c * 4 + 1) (get rgb (c * 3 + 1));
    set array (c * 4 + 2) (get rgb (c * 3 + 2));
    set array (c * 4 + 3) 0;
  done;
  array

let show_exn f =
  try 
    f ()
  with exn ->
    Printf.printf "Exception: %s (%s)\n%!" (Printexc.to_string exn) (Printexc.get_backtrace ());
    raise exn

let view ?packing url http_mt () =
  let drawing_area = GMisc.drawing_area ?packing ~width:640 ~height:480 () in
  (* let pixmap = GDraw.pixmap ~width:640 ~height:480 () in *)
  (* let drawable = new GDraw.drawable drawing_area#misc#window in *)
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
  let count = ref 0 in 
  let received_data (data : BoundaryDecoder.data) =
    show_exn @@ fun () ->
      let content_length = int_of_string (List.assoc "Content-Length" data.data_header) in
      (* Printf.printf "Received data (%d/%d bytes)\n%!" (String.length data.data_content) content_length; *)
      if save_images then (
	let filename = Printf.sprintf "output/%04d.jpg" !count in
	incr count;
	output_file ~filename ~text:data.data_content;
      );
      let jpeg_image = Jpeg.decode_int (Jpeg.array_of_string data.data_content) in
      let (width, height) = (jpeg_image.Jpeg.image_width, jpeg_image.Jpeg.image_height) in
      let rgb_data = expand_rgb width height jpeg_image.Jpeg.image_data in
      image := Some (Cairo.Image.create_for_data8 rgb_data Cairo.Image.RGB24 width height, width, height);
      drawing_area#misc#draw None
  in
  let header_finished header =
    let boundary = 
      let contenttype = List.assoc "Content-Type" header in
      Printf.printf "contenttype: %s\n" contenttype;
      match Pcre.extract ~full_match:false ~pat:"^multipart/x-mixed-replace; *boundary=(?:--)?(.*)" contenttype with
      | [|boundary|] -> 
	Printf.printf "boundary: %s\n%!" boundary;
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
      Printf.printf "HTTP: %d %s\n%!" code message;
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
      Printf.printf "Processing header: %d %s\n%!" (String.length trimmed_str) trimmed_str;
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
  let urls = read_streams () in
  List.iter (fun url -> ignore (view url http_mt ~packing:vbox#add ())) urls;
  main_window#show ();
  GMain.Main.main ()

let _ = main ()
