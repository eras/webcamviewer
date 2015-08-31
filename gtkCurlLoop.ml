open Batteries
open Common

let string_of_cond = function
  | `ERR -> "ERR"
  | `HUP -> "HUP"
  | `IN -> "IN"
  | `NVAL -> "NVAL"
  | `OUT -> "OUT"
  | `PRI -> "PRI"
    
let make () =
  let http_mt = Curl.Multi.create () in
  let http_mt_fds = Hashtbl.create 10 in
  let notify_removals = ref [] in
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
    (match Curl.Multi.remove_finished http_mt with
    | Some (http, code) ->
       ( match List.assoc http !notify_removals with
       | exception Not_found -> ()
       | notify_function ->
         let () = notify_function () in
         notify_removals := List.remove_assoc http !notify_removals;
       )
    | None -> ()
    );
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
      let was_member = Hashtbl.mem http_mt_fds fd in
      if was_member then
	GMain.Io.remove (Hashtbl.find http_mt_fds fd);
      Hashtbl.remove http_mt_fds fd;
      match gtk_cond_of_curl_poll poll with
      | [] ->
         (* OK, we're done here *)
         ()
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
  let interface = object
    method multi = http_mt
    method notify_removal_of http notify_function = notify_removals := (http, notify_function) :: !notify_removals
  end in
  interface
