exception Closed
  
type t = {
  work_queue : WorkQueue.t;
  work       : (unit -> unit) Queue.t;
  mutex      : Mutex.t;
  mutable closed : bool;
  mutable running : bool;
}

let create : WorkQueue.t -> t =
  fun work_queue ->
    { work_queue;
      work   = Queue.create ();
      mutex  = Mutex.create ();
      closed = false;
      running = false; }

let worker t () =
  let rec loop () =
    let work =
      try Some (Queue.take t.work)
      with exn -> None
    in
    Mutex.unlock t.mutex;
    let () =
      match work with
      | None -> ()
      | Some work ->
        let () =
          try work ()
          with exn ->
            Printf.eprintf "OrderedWorkQueue caught an unhandled exception: %s\nBacktrace:%s\n%!" (Printexc.to_string exn) (Printexc.get_backtrace ());
        in
        ()
    in
    Mutex.lock t.mutex;
    let work_left = not (Queue.is_empty t.work) in
    if work_left then loop ();
  in
  Mutex.lock t.mutex;
  loop ();
  t.running <- false;
  Mutex.unlock t.mutex

let submit_direct =
  fun ~set_closed t work ->
    Mutex.lock t.mutex;
    if not set_closed && t.closed then (
      Mutex.unlock t.mutex;
      raise Closed
    ) else if set_closed then
      t.closed <- true;
    Queue.add work t.work;
    if not t.running then (
      t.running <- true;
      WorkQueue.async t.work_queue (worker t);
    );
    Mutex.unlock t.mutex

let submit : t -> (unit -> unit) -> unit = submit_direct ~set_closed:false

let finish : t -> unit =
  fun t ->
    let msg = Event.new_channel () in
    submit_direct ~set_closed:true t (fun () -> Event.sync (Event.send msg ()));
    Event.sync (Event.receive msg)
