open Batteries

let (@@) a b = a b

let destroy () =
  GMain.Main.quit ()

let url = "http://cam1.sec.mf/videostream.cgi"
let user = "admin"
let password = ""

let trim_crnl str =
  if String.length str >= 2
  then String.sub str 0 (String.length str - 2)
  else str

let view ?packing http_mt () =
  let widget = GMisc.drawing_area ?packing ~width:640 ~height:480 () in
  let http = Curl.init () in
  let header = ref [] in
  Curl.set_url http url;
  Curl.set_userpwd http (user ^ ":" ^ password);
  let boundary_decoder = ref (fun _ -> assert false) in
  Curl.set_writefunction http (fun str ->
    Printf.printf "%d bytes\n%!" (String.length str) (* str *);
    let decoder = BoundaryDecoder.feed_decoder (!boundary_decoder ()) str 0 (String.length str) in
    boundary_decoder := (fun () -> decoder);
    String.length str
  );
  let count = ref 0 in 
  let received_data (data : BoundaryDecoder.data) =
    let content_length = int_of_string (List.assoc "Content-Length" data.data_header) in
    Printf.printf "Received data (%d/%d bytes)\n%!" (String.length data.data_content) content_length;
    let filename = Printf.sprintf "output/%04d.jpg" !count in
    incr count;
    output_file ~filename ~text:data.data_content;
    let jpeg = Jpeg.decode (Jpeg.array_of_string data.data_content) in
    ()
  in
  let header_finished header =
    let boundary = 
      let contenttype = List.assoc "Content-Type" header in
      Printf.printf "contenttype: %s\n" contenttype;
      match Pcre.extract ~full_match:false ~pat:"^multipart/x-mixed-replace; *boundary=(.*)" contenttype with
      | [|boundary|] -> boundary
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
    let trimmed_str = trim_crnl str in
    Printf.printf "Processing header: %d %s\n%!" (String.length trimmed_str) trimmed_str;
    !receive_header trimmed_str;
    String.length str
  );
  Curl.Multi.add http_mt http;
  widget

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
  ignore (main_window#connect#destroy ~callback:destroy);
  let vbox = GPack.vbox ~packing:main_window#add () in
  let quit_button = GButton.button ~label:"Quit" ~packing:vbox#add () in
  ignore (quit_button#connect#clicked ~callback:destroy);
  let view1 = view http_mt ~packing:vbox#add () in
  main_window#show ();
  GMain.Main.main ()

let _ = main ()
