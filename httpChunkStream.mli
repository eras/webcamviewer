val start :
  on_eof:(unit -> unit) ->
  < multi : Curl.Multi.mt;
    notify_removal_of : Curl.t -> (unit -> unit) -> unit;
    .. > ->
  string ->
  (BoundaryDecoder.data -> unit) ->
  unit
