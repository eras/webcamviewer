open Batteries

let (@@) a b = a b

type boundary_case = BoundaryEdge | OnBoundary | NoBoundary of (string * char)
    
let match_boundary boundary buf boundary_at at =
  let ch = buf.[at] in
  if boundary_at = String.length boundary then
    BoundaryEdge
  else if boundary.[boundary_at] = ch then
    OnBoundary
  else
    NoBoundary 
	( (if boundary_at = 0 then "" else String.sub boundary 0 boundary_at), 
        ch )

type dump_state = DumpHeader | DumpData

(* let dump_boundaries chan boundary = *)
(*   let buf = String.make 10240 ' ' in *)
(*   let outbuf = Buffer.create 1024 in *)
(*   let boundary_match = match_boundary ("\r\n" ^ boundary ^ "\r\n") buf in *)
(*   let end_of_line = match_boundary "\r\n" buf in *)
(*   let headerbuf = Buffer.create 1024 in *)
(*   let found_header_row key value = *)
(* (\* Printf.printf "Got: %s = %s\n%!" key value; *\) *)
(*     Buffer.clear headerbuf *)
(*   in *)
(*   let found_header_end () = *)
(* (\* Printf.printf "Got header end! %s\n%!" (Buffer.contents headerbuf); *\) *)
(*   Buffer.clear headerbuf *)
(*   in *)
(*   let found_boundary () = *)
(* (\* Printf.printf "Got boundary! size of data: %d\n%!" (Buffer.length outbuf); *\) *)
(*     Buffer.clear outbuf *)
(*   in *)
(*   let rec aux state boundary_at offset = *)
(*     match wrap (chan#input buf 0) (String.length buf) with *)
(*     | Ok length -> *)
(* 	let rec find_boundary state boundary_at at = *)
(* 	  if at < length then *)
(* 	    match state with *)
(* 	    | DumpHeader -> *)
(* 	      begin *)
(* 		match end_of_line boundary_at at with *)
(* 		| NoBoundary (remainder, ch) -> *)
(* 		  if remainder <> "" then *)
(* 		    Buffer.add_string headerbuf remainder; *)
(* 		  Buffer.add_char headerbuf ch; *)
(* 		  find_boundary DumpHeader 0 (at + 1) *)
(* 		| BoundaryEdge ->  *)
(* 		  let b = Buffer.contents headerbuf in *)
(* 		  if b <> "" then *)
(* 		    begin *)
(* 		      let key, value = split_key_value b in *)
(* 		      found_header_row key value; *)
(* 		      find_boundary DumpHeader 0 (at) *)
(* 		    end *)
(* 		  else *)
(* 		    begin *)
(* 		      (\* End of headers.. *\) *)
(* 		      found_header_end (); *)
(* 		      find_boundary DumpData 0 (at) *)
(* 		    end *)
(* 		  | OnBoundary -> *)
(* 		      find_boundary DumpHeader (boundary_at + 1) (at + 1) *)
(* 		end *)
(* 	    | DumpData -> *)
(* 		begin *)
(* 		  match boundary_match boundary_at at with *)
(* 		  | NoBoundary (remainder, ch) -> *)
(* 		      (\*Printf.printf "%Ld: Didn't get any %d/%d! '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) ch;*\) *)
(* 		      (\*Buffer.add_substring outbuf boundary_match 0 boundary_at;*\) *)
(* 		      if remainder <> "" then *)
(* 			Buffer.add_string outbuf remainder; *)
(* 		      Buffer.add_char outbuf ch; *)
(* 		      find_boundary DumpData 0 (at + 1) *)
(* 		  | BoundaryEdge -> *)
(* 		      found_boundary (); *)
(* 		      find_boundary DumpHeader 0 (at) *)
(* 		  | OnBoundary ->  *)
(* 		      (\*Printf.printf "%Ld: Got some.. at %d/%d '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) (ch);*\) *)
(* 		      find_boundary DumpData (boundary_at + 1) (at + 1) *)
(* 		end *)
(* 	  else *)
(* 	    state, boundary_at *)
(* 	in *)
(* 	(\*Printf.printf "At: %Ld\n%!" offset;*\) *)
(* 	let state, boundary_at = (find_boundary state boundary_at 0) in *)
(* 	aux state boundary_at (Int64.add offset (Int64.of_int length)) *)
(*   | Bad End_of_file -> () *)
(*   | Bad exn -> raise exn *)
(* in *)
(* aux DumpData 2 0L (\* the boundary is prefixed with \r\n\r\n *\) *)

type data = 
  { data_header : (string * string) list;
    data_content : string;
    data_time : float }

(* Call the continuation with the buffer filled with at most n bytes; 
   tell how many bytes were filled *)
type 'a feed_data = FeedData of ((string * int) * ((int, exn) result -> 'a feed_data))

let rec feed_decoder feed_data src_buf src_ofs src_len =
  let FeedData ((dst_buf, dst_buf_size), cont) = feed_data in
  let remaining = max 0 (src_len - src_ofs) in
  let consume = min dst_buf_size remaining in
  String.blit src_buf src_ofs dst_buf 0 consume;
  let cont = cont (Ok consume) in
  if consume < remaining
  then feed_decoder feed_data src_buf (src_ofs + consume) (src_len - consume)
  else cont

let decode_boundaries boundary data_callback : unit feed_data =
  let boundary = "--" ^ boundary in
  let buf = String.make 10240 ' ' in
  let outbuf = Buffer.create 1024 in
  let boundary_match = match_boundary ("\r\n" ^ boundary ^ "\r\n") buf in
  let end_of_line = match_boundary "\r\n" buf in
  let headerbuf = Buffer.create 1024 in
  let header = ref [] in
  let begin_time = ref 0.0 in
  let found_header_row key value =
    header := (key, value) :: !header;
	  (*Printf.printf "Got: %s = %s\n%!" key value;*)
    Buffer.clear headerbuf
  in
  let found_header_end () =
    (*Printf.printf "Got header end! %s: %d\n%!" (Buffer.contents headerbuf) (Buffer.length outbuf);*)
    let v = 
	{ data_header = !header;
	  data_content = Buffer.contents outbuf;
	  data_time = !begin_time }
    in
    Buffer.clear headerbuf;
    Buffer.clear outbuf;
    header := [];
    v
  in
  let found_boundary () =
(*Printf.printf "Got boundary! size of data: %d\n%!" (Buffer.length outbuf);*)
    ()
  in
  let first = ref true in
  let request_data buffer n cont : _ feed_data =
    FeedData ((buffer, n), cont)
  in
  let rec aux state boundary_at offset : _ feed_data =
    request_data buf (String.length buf) @@  
	function
      | Ok length ->
  	  let rec find_boundary responses state boundary_at at =
        (* Printf.printf "Finding boundary at %d %d\n%!" boundary_at at; *)
  	    if at < length then
  	      match state with
  	      | DumpHeader ->
  		begin
  		  match end_of_line boundary_at at with
  		  | NoBoundary (remainder, ch) ->
  		    if remainder <> "" then
  		      Buffer.add_string headerbuf remainder;
  		    Buffer.add_char headerbuf ch;
  		    find_boundary responses DumpHeader 0 (at + 1)
  		  | BoundaryEdge -> 
  		    let b = Buffer.contents headerbuf in
  		    if b <> "" then
  		      begin
  			let key, value = Utils.split_key_value b in
  			found_header_row key value;
  			find_boundary responses DumpHeader 0 (at)
  		      end
  		    else
  		      begin
  		      (* End of headers.. *)
  			let v = found_header_end () in
   	                let rs = 
  			  if !first then
  			    responses
  			  else
  			    v::responses 
  			in
  			first := false;
  			begin_time := Unix.gettimeofday ();
  			  find_boundary rs DumpData 0 (at)
  			end
                | OnBoundary ->
  		    find_boundary responses DumpHeader (boundary_at + 1) (at + 1)
  	      end
              | DumpData ->
  	      begin
  		      (* Printf.printf "Dumping data\n%!"; *)
  		match boundary_match boundary_at at with
  		| NoBoundary (remainder, ch) ->
  			    (*Printf.printf "%Ld: Didn't get any %d/%d! '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) ch;*)
  			    (*Buffer.add_substring outbuf boundary_match 0 boundary_at;*)
  		  if remainder <> "" then
  		    Buffer.add_string outbuf remainder;
  		  Buffer.add_char outbuf ch;
  		  find_boundary responses DumpData 0 (at + 1)
  		| BoundaryEdge ->
  		  found_boundary ();
  		  find_boundary responses DumpHeader 0 (at)
  		| OnBoundary -> 
  			    (*Printf.printf "%Ld: Got some.. at %d/%d '%c' vs '%c'\n%!" (Int64.add offset (Int64.of_int at)) (boundary_at) at (boundary_match.[boundary_at]) (ch);*)
  		  find_boundary responses DumpData (boundary_at + 1) (at + 1)
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
      | Bad End_of_file -> assert false (* [<>] *)
      | Bad exn -> raise exn
in
  aux DumpData 2 0L (* the boundary is prefixed with \r\n\r\n *)
