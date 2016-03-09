let (@@) a b = a b

type source = {
  source_name : string;
  source_url  : string;
}

type config = {
  config_sources : source list;
  config_output_base : string;
}

let pi2 = 8. *. atan 1.

let show_exn f =
  try 
    f ()
  with exn ->
    Printf.printf "Exception: %s (%s)\n%!" (Printexc.to_string exn) (Printexc.get_backtrace ());
    raise exn

let button_number ev =
  match GdkEvent.get_type ev, GdkEvent.unsafe_cast ev with
  | `BUTTON_PRESS, ev ->
     Some (GdkEvent.Button.button ev)
  | _ -> 
     None

let when_button n f ev =
  if button_number ev = Some n then
    f ev
  else
    false

let path_of_tm { Unix.tm_sec = sec;
                 tm_min = min;
                 tm_hour = hour;
                 tm_mday = mday;
                 tm_mon = mon;
                 tm_year = year } =
  Printf.sprintf
    "%04d-%02d-%02d/%02d"
    (year + 1900)
    (mon + 1)
    (mday)
    (hour)

let string_of_date { Unix.tm_mday = mday;
                    tm_mon = mon;
                    tm_year = year } =
  Printf.sprintf
    "%04d-%02d-%02d"
    (year + 1900)
    (mon + 1)
    (mday)

let path_of_time t = path_of_tm (Unix.localtime t)

let trim_crnl str =
  if String.length str >= 2
  then String.sub str 0 (String.length str - 2)
  else str

let string_of_tm { Unix.tm_sec = sec;
                   tm_min = min;
                   tm_hour = hour;
                   tm_mday = mday;
                   tm_mon = mon;
                   tm_year = year } =
  Printf.sprintf
    "%04d-%02d-%02d %02d:%02d:%02d"
    (year + 1900)
    (mon + 1)
    (mday)
    (hour)
    (min)
    (sec)

let string_of_time t =
  string_of_tm (Unix.localtime t)

let frac x = fst (modf x)

let string_of_time_us t =
  string_of_tm (Unix.localtime t) ^ Printf.sprintf ".%06d" (int_of_float (frac t *. 1000000.0))

