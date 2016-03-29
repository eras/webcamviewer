open Batteries

type queue = {
  mutex           : Mutex.t;
  work_available  : Semaphore.t;
  work_pending    : int ref;
  work            : (unit -> unit) option Queue.t;
}

type t = {
  queue   : queue;
  threads : Thread.t list;
}

let worker (queue : queue) =
  let rec loop () =
    Semaphore.down queue.work_available;
    Mutex.lock queue.mutex;
    let work = Queue.pop queue.work in
    decr queue.work_pending;
    Mutex.unlock queue.mutex;
    match work with
    | None -> `Fin
    | Some work ->
      ( try
          work ()
        with exn ->
          Printf.eprintf "WorkQueue exception: %s\n" (Printexc.to_string exn) );
      loop ()
  in
  `Fin = loop ()

(** [create number_of_threads] *)
let create : int -> t =
  fun n_threads ->
    let queue = {
      mutex          = Mutex.create ();
      work_available = Semaphore.create 0;
      work           = Queue.create ();
      work_pending   = ref 0;
    } in
    let threads =
      (0 --^ n_threads)
      |> Enum.map (fun _ -> Thread.create worker queue)
      |> List.of_enum
    in
    { queue; threads }

let finish : t -> unit =
  fun t ->
    Mutex.lock t.queue.mutex;
    let () = (0 --^ List.length t.threads) |> Enum.iter @@ fun _ ->
      Queue.add None t.queue.work;
      Semaphore.up t.queue.work_available;
    in
    Mutex.unlock t.queue.mutex;
    List.iter Thread.join t.threads

let async : t -> (unit -> unit) -> unit =
  fun t work ->
    Mutex.lock t.queue.mutex;
    Queue.add (Some work) t.queue.work;
    Semaphore.up t.queue.work_available;
    incr t.queue.work_pending;
    Mutex.unlock t.queue.mutex

let sync : t -> (unit -> 'result) -> 'result =
  fun t work ->
    let msg = Event.new_channel () in
    async t (fun () -> Event.sync (Event.send msg (work ())));
    Event.sync (Event.receive msg)

let queue_length : t -> int =
  fun t ->
    Mutex.lock t.queue.mutex;
    let v = !(t.queue.work_pending) in
    Mutex.unlock t.queue.mutex;
    v
