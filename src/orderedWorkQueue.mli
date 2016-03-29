type t

exception Closed

val create : WorkQueue.t -> t

val submit : t -> (unit -> unit) -> unit

val finish : t -> unit
