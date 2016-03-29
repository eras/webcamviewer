val view :
  work_queue:WorkQueue.t ->
  ?packing:(GObj.widget -> unit) ->
  Common.config ->
  Common.source ->
  < multi : Curl.Multi.mt;
    notify_removal_of : Curl.t -> (unit -> unit) -> unit > ->
  unit ->
  < drawing_area: GMisc.drawing_area;
    finish : (unit -> unit) -> unit;
  >
