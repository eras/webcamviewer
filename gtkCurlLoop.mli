val make :
  unit ->
  < multi : Curl.Multi.mt;
    notify_removal_of : Curl.t -> (unit -> unit) -> unit >
