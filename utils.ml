open Batteries

let split_key_value str =
  let colon = String.index str ':' in
  let key, value = 
    String.sub str 0 colon,
    String.sub str (colon + 2) (String.length str - (colon + 2))
  in
  key, value

let split_http_header str =
  match Pcre.extract ~full_match:false ~pat:"^HTTP/1\\.1 ([0-9]+) (.*)" str with
  | [|code; message|] -> (int_of_string code, message)
  | _ -> failwith "Failed to parse HTTP header"

