val view :
  ?packing:(GObj.widget -> unit) ->
  Common.config ->
  Common.source ->
  Curl.Multi.mt ->
  unit ->
  GMisc.drawing_area
    
