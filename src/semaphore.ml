type t = {
  mutable n : int;
  mutex	    : Mutex.t;
  condition : Condition.t
}

let create n = { n; mutex = Mutex.create (); condition = Condition.create () }

let up t =
  Mutex.lock t.mutex;
  t.n <- t.n + 1;
  if t.n > 0 then Condition.broadcast t.condition;
  Mutex.unlock t.mutex

let down t =
  Mutex.lock t.mutex;
  let rec loop () =
    if t.n <= 0 then (
      Condition.wait t.condition t.mutex;
      loop ()
    ) else (
      () (* done *)
    )
  in
  loop ();
  t.n <- t.n - 1;
  Mutex.unlock t.mutex
