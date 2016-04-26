open Batteries

let (@@) a b = a b

type boundary_case = FoundBoundary | OnBoundary | NoBoundary of (string * char option)
and boundary_continue = int * boundary_case
    
let match_boundary boundary buf boundary_at at =
  if boundary_at = String.length boundary then
    (* We have found the end of the boundary *)
    (0, FoundBoundary)
  else
    let buf_ch = buf.[at] in
    if boundary.[boundary_at] = buf_ch then
    (* We are currently (possibly) over a boundary.. *)
      (boundary_at + 1, OnBoundary)
    else
    (* We might have thought we were on a boundary but it turns out we
       weren't (though we didn't think that if boundary_at happened to
       be zero). Nevertheles, return the data we thought was part of
       the boundary as something that is real data. *)
      if boundary.[0] = buf_ch
      then (1, NoBoundary (String.sub boundary 0 boundary_at, None)) (* turns out a new boundary maybe begins here *)
      else (0, NoBoundary (String.sub boundary 0 boundary_at, Some buf_ch))

type dump_state = DumpHeader | DumpData

type data = 
  { data_header : (string * string) list;
    data_content : string;
    data_time : float }

(* Call the continuation with the buffer filled with at most n bytes; 
   tell how many bytes were filled *)
type 'a feed_data = FeedData of ((string * int) * ((int, exn) result -> 'a feed_data))

let depth = ref 0

let with_depth f =
  incr depth;
  try 
    let v = f () in
    decr depth;
    v
  with exn -> 
    decr depth;
    raise exn

let rec feed_decoder feed_data src_buf src_ofs src_len =
  with_depth @@ fun () ->
    let FeedData ((dst_buf, dst_buf_size), cont) = feed_data in
    let consume = min dst_buf_size src_len in
    (* Printf.printf "Feeding %d %d %d %d <%s>\n" !depth src_ofs src_len consume (String.sub src_buf src_ofs consume); *)
    String.blit src_buf src_ofs dst_buf 0 consume;
    let cont = cont (Ok consume) in
    if consume < src_len
    then feed_decoder cont src_buf (src_ofs + consume) (src_len - consume)
    else cont

let decode_boundaries boundary (data_callback : data -> unit) : unit feed_data =
  let work_buf = String.make 10240 ' ' in (* working buffer; incoming data *)
  let response_buf = Buffer.create 1024 in (* buffer that collects response data *)
  let boundary_match = match_boundary ("\r\n--" ^ boundary ^ "\r\n") work_buf in
  let end_of_line = match_boundary "\r\n" work_buf in
  let header_buf = Buffer.create 1024 in
  let header = ref [] in
  let begin_time = ref 0.0 in
  let found_header_row key value =
    header := (key, value) :: !header;
    (* Printf.printf "Got: %s = %s\n%!" key value; *)
    Buffer.clear header_buf
  in
  let found_header_end () =
    (* Printf.printf "Got header end! %s: %d\n%!" (Buffer.contents header_buf) (Buffer.length response_buf); *)
    ()
  in
  let found_boundary () =
    (* Printf.printf "Got boundary! size of data: %d\n%!" (Buffer.length response_buf); *)
    let v = 
	{ data_header = List.rev !header;
	  data_content = Buffer.contents response_buf;
	  data_time = !begin_time }
    in
    Buffer.clear header_buf;
    Buffer.clear response_buf;
    header := [];
    v
  in
  let first = ref true in
  let request_data buffer n cont : _ feed_data =
    FeedData ((buffer, n), cont)
  in
  let rec aux state boundary_at offset : _ feed_data =
    request_data work_buf (String.length work_buf) @@  
	function
      | Ok length ->
  	  let rec find_boundary responses state boundary_at at =
  	    if at < length then
	      (* let _ = *)
	      (*   Printf.printf "Finding boundary at %d %d%!" boundary_at at; *)
	      (* 	Printf.printf "%c %c\n%!" work_buf.[at] (if boundary_at < String.length boundary then boundary.[boundary_at] else '!'); *)
	      (* in *)
  	      match state with
  	      | DumpHeader ->
  		begin
		  let (boundary_at, boundary_case) = end_of_line boundary_at at in
  		  match boundary_case with
  		  | NoBoundary (remainder, ch) ->
  		    Buffer.add_string header_buf remainder;
		    Option.may (Buffer.add_char header_buf) ch;
  		    find_boundary responses DumpHeader boundary_at (at + 1)
  		  | FoundBoundary -> 
  		    let b = Buffer.contents header_buf in
  		    if b <> "" then
  		      begin
  			let key, value = Utils.split_key_value b in
  			found_header_row key value;
  			find_boundary responses DumpHeader boundary_at (at)
  		      end
  		    else
  		      begin
  			(* End of headers.. *)
  			let v = found_header_end () in
  	                  first := false;
   	                  begin_time := Unix.gettimeofday ();
  			  find_boundary responses DumpData 0 (at)
  			end
                | OnBoundary ->
  		    find_boundary responses DumpHeader boundary_at (at + 1)
  	      end
              | DumpData ->
  	      begin
  		(* Printf.printf "Dumping data\n%!"; *)
		let (boundary_at, boundary_case) = boundary_match boundary_at at in
  		match boundary_case with
  		| NoBoundary (remainder, ch) ->
  		  (* Printf.printf "%Ld: Didn't get any %d/%d! '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) ch; *)
  			    (* Buffer.add_substring response_buf boundary_match 0 boundary_at; *)
  		  Buffer.add_string response_buf remainder;
		  Option.may (Buffer.add_char response_buf) ch;
  		  find_boundary responses DumpData boundary_at (at + 1)
  		| FoundBoundary ->
  		  let v = found_boundary () in
   	          let responses = 
  		    if !first then
  		      responses
  		    else
  		      v::responses 
  		  in
  		  find_boundary responses DumpHeader 0 (at)
  		| OnBoundary -> 
  		  (* Printf.printf "%Ld: Got some.. at %d/%d '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) (ch); *)
  		  find_boundary responses DumpData boundary_at (at + 1)
  	      end
  	    else
  	      List.rev responses, state, boundary_at
  	  in
  	    (* Printf.printf "At: %Ld %d\n%!" offset boundary_at; *)
  	  let responses, state, boundary_at = (find_boundary [] state boundary_at 0) in
	  let rec feed_responses rs =
	    match rs with
	    | [] -> aux state boundary_at (Int64.add offset (Int64.of_int length))
	    | r::rs ->
	      data_callback r;
	      feed_responses rs
	  in
	  feed_responses responses;
      | Error End_of_file -> assert false (* [<>] *)
      | Error exn -> raise exn
in
  aux DumpData 2 0L (* the boundary is prefixed with \r\n\r\n *)
