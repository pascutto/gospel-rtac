type t = private { f : int }

val get : t -> int
(*@ y = get t
    ensures y = t.f *)
