val test_forall : int -> int -> int
(*@ r = test_forall i j
    requires forall x. i <= x < j -> x > 0 *)

val double_forall : int -> int -> unit
(*@ double_forall lo hi
    requires forall i. lo <= i < hi -> forall j. i <= j < hi -> i <= j *)

val power : int -> int -> int
(*@ r = power x n
    requires n >=0
    ensures  r = pow x n *)
