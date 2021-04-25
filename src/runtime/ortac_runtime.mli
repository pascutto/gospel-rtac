type term = Pre of string | Post of string | XPost of string

type error_kind = Violated | RuntimeExn of exn

type error =
  | Condition of {
      loc : Ppxlib.location;
      fun_name : string;
      term : term;
      error_kind : error_kind;
    }
  | Unexpected_exception of {
      loc : Ppxlib.location;
      fun_name : string;
      exn : exn;
    }

val mk_condition : Ppxlib.location -> string -> term -> error_kind -> error

val mk_unexpected_exception : Ppxlib.location -> string -> exn -> error

exception Error of error list

module Errors : sig
  type t

  val empty : unit -> t
  (** [empty] create a new empty error container *)

  val register : error -> t -> unit
  (** [register a l] add the element [a] to [l] *)

  val raise_errors : t -> 'a
  (** [raise_errors l] raises [Error] with the content of [l] *)

  val report : t -> unit
  (** [report l] prints the content of [l] *)

  val report_and_raise : t -> 'a
  (** [report_and_raise l] report the content of [l] and raise it as an [Error] *)

  val check_and_do : (t -> unit) -> t -> unit
  (** [check_and_do f l] apply [f] to [l] if [l] is not empty *)
end

module Z : sig
  include module type of Z

  val pow : t -> t -> t

  val exists : t -> t -> (t -> bool) -> bool
  (** [exists i j p] is [true] iff the predicate there exists [k] within [i] and
      [j], included, for which [p] holds. *)

  val forall : t -> t -> (t -> bool) -> bool
  (** [forall i j p] is [true] iff the predicate `p` holds forall [k] within [i]
      and [j], included. *)
end

module Array : sig
  val create : Z.t -> 'a -> 'a array

  val get : 'a array -> Z.t -> 'a

  val length : 'a array -> Z.t
end
