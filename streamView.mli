val view :
  ?packing:(GObj.widget -> unit) ->
  Common.config ->
  Common.source ->
  < multi : Curl.Multi.mt;
    notify_removal_of : Curl.t -> (unit -> unit) -> unit > ->
  unit ->
  GMisc.drawing_area
    
