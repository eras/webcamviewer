type t

(** [create number_of_threads] *)
val create: int -> t

val async : t -> (unit -> unit) -> unit

val sync : t -> (unit -> 'result) -> 'result

val finish : t -> unit
    
