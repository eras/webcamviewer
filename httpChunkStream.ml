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

let start ~on_eof http_mt url process =
  let http = Curl.init () in
  Curl.set_debugfunction http (fun _ _ str -> Printf.fprintf stderr "curl: %s\n%!" str);
  http_mt#notify_removal_of http (fun _ -> on_eof ());
  let header = ref [] in
  Curl.set_url http url;
  let boundary_decoder = ref (fun _ -> assert false) in
  Curl.set_failonerror http true;
  Curl.set_writefunction http (fun str ->
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
  Curl.Multi.add http_mt#multi http

