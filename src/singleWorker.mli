(* A type of queue where only at most one units may be
   in at a time. If another job unit is submitted while
   the previous has not been started, the previous job unit
   will be replaced *)

type t

val create : WorkQueue.t -> t

val submit : t -> (unit -> unit) -> unit

val finish : t -> unit

