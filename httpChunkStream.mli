(** [start ~on_eof http_mt url callback] starts retrieving the given
    URL, calling callback on received chunks. When an end-of-file is
    reached the on_eof handler is called (ie. in a image streaming
    case the handler might restart the transfer). *)
val start :
  on_eof:(unit -> unit) ->
  < multi : Curl.Multi.mt;
    notify_removal_of : Curl.t -> (unit -> unit) -> unit;
    .. > ->
  string ->
  (BoundaryDecoder.data -> unit) ->
  < finish : (unit -> unit) -> unit >
