open Batteries

let split_key_value str =
  let colon = String.index str ':' in
  let key, value = 
    String.sub str 0 colon,
    String.sub str (colon + 2) (String.length str - (colon + 2))
  in
  key, value

let split_http_header str =
  try 
    let fields = Pcre.extract ~full_match:false ~pat:"^HTTP/[^ ]* ([0-9]+) (.*)" str in
    ( match fields with
    | [|code; message|] -> (int_of_string code, message)
    | _ -> failwith "Failed to parse HTTP header" )
  with Not_found -> 
    failwith ("Failed to parse HTTP header: " ^ str)
      

let indices_of pred str =
  let indices = ref [] in
  for c = String.length str - 1 downto 0 do
    if pred (str.[c]) then
      indices := c::!indices
  done;
  !indices

let mkdir_rec path =
  let separators = indices_of ((=) '/') path in
  let prepaths = (separators @ [String.length path]) |> List.map @@ fun index ->
    String.sub path 0 index
  in
  let prepaths = List.filter ((<>) "") prepaths in
  let mkdir dir =
    try Unix.mkdir dir 0o750
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  in 
  prepaths |> List.iter mkdir

