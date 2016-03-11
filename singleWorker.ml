type work = unit -> unit

type enqueued = {
  e_work1 : work;
  e_work2 : work option;
}

type working = {
  w_work2 : work option;
}

type state =
  | Enqueued of enqueued
  | Working of working
  | Idle

type t = {
  work_queue    : WorkQueue.t;
  mutex         : Mutex.t;
  mutable state : state;
}

let create work_queue =
  {
    work_queue;
    mutex     = Mutex.create ();
    state     = Idle;
  }

let rec run_work t () =
  Mutex.lock t.mutex;
  let work =
    match t.state with
    | Idle -> assert false
    | Working _ -> assert false
    | Enqueued e ->
      t.state <- Working { w_work2 = e.e_work2 };
      e.e_work1
  in
  Mutex.unlock t.mutex;
  let () =
    try
      work ()
    with exn ->
      Printf.eprintf "SingleWorker caught an exception: %s\n%!" (Printexc.to_string exn)
  in
  Mutex.lock t.mutex;
  let () =
    match t.state with
    | Idle -> assert false
    | Enqueued _ -> assert false
    | Working { w_work2 = Some work } ->
      t.state <- Enqueued { e_work1 = work;
                            e_work2 = None };
      WorkQueue.async t.work_queue (run_work t)
    | Working { w_work2 = None } ->
      t.state <- Idle;
  in
  Mutex.unlock t.mutex

let submit t work =
  Mutex.lock t.mutex;
  let () =
    match t.state with
    | Idle ->
      t.state <- Enqueued { e_work1 = work; e_work2 = None };
      WorkQueue.async t.work_queue (run_work t)
    | Working _ ->
      t.state <- Working { w_work2 = Some work }
    | Enqueued enqueued ->
      t.state <- Enqueued { enqueued with e_work2 = Some work }
  in
  Mutex.unlock t.mutex

let finish t =
  Mutex.lock t.mutex;
  let () =
    match t.state with
    | Idle -> ()
    | Working _ -> t.state <- Working { w_work2 = None }
    | Enqueued _ -> t.state <- Idle
  in
  Mutex.unlock t.mutex
