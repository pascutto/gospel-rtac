open Fmt

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

let mk_condition loc fun_name term error_kind =
  Condition { loc; fun_name; term; error_kind }

let mk_unexpected_exception loc fun_name = function
  | (Out_of_memory | Stack_overflow) as e -> raise e
  | exn -> Unexpected_exception { loc; fun_name; exn }

let styled_list l pp = List.fold_left (fun acc x -> styled x acc) pp l

let pp_kind ppf = function
  | Violated -> (styled `Yellow string) ppf "violated"
  | RuntimeExn e ->
      pf ppf "%a:@ %a"
        (styled `Yellow string)
        "not executable"
        (styled `Bold string)
        (Printexc.to_string e)

let pp_term =
  using
    (function
      | Pre t -> ("pre-condition", t)
      | Post t -> ("post-condition", t)
      | XPost t -> ("exceptional post-condition", t))
    (fun ppf (p, t) ->
      pf ppf "%a @[%a@]"
        (styled_list [ `Yellow; `Underline ] string)
        p
        (styled `Bold string)
        t)

let pp_loc = styled `Bold Ppxlib.Location.print

let report ppf = function
  | Condition { loc; fun_name; term; error_kind } ->
      pf ppf "%a@\n %a: Gospel specification unmet in function %a:@\n %a is %a"
        pp_loc loc
        (styled `Red string)
        "Runtime error"
        (styled `Blue string)
        fun_name
        (styled `Bold pp_term)
        term pp_kind error_kind
  | Unexpected_exception { loc; fun_name; exn } ->
      pf ppf "%a@\n %a: Undeclared exeception raised by %a:@\n%a" pp_loc loc
        (styled `Red string)
        "Runtime error"
        (styled `Blue string)
        fun_name
        (styled `Bold string)
        (Printexc.to_string exn)

exception Error of error list

let error e = raise (Error e)

module Errors = struct
  type t = error list ref

  let empty () = ref []

  let register e l = l := e :: !l

  let raise_errors l = error !l

  let report l = Fmt.(epr "%a@." (list ~sep:(any "@\n") report) !l)

  let report_and_raise l =
    report l;
    raise_errors l

  let check_and_do f l = match !l with [] -> () | _ -> f l
end

module Z = struct
  include Z

  let pow x n =
    try pow x (to_int n) with Overflow -> invalid_arg "Exponent too big"

  let rec forall start stop p =
    start > stop || (p start && forall (succ start) stop p)

  let rec exists start stop p =
    start <= stop && (p start || exists (succ start) stop p)
end

module Array = struct
  let create z =
    if Z.(z > of_int Sys.max_array_length) then
      raise (Invalid_argument "Array length too big")
    else Array.make (Z.to_int z)

  let get arr z =
    if Z.(z < zero || z >= of_int (Array.length arr)) then
      raise (Invalid_argument "Out of array bounds")
    else Array.unsafe_get arr (Z.to_int z)

  let length arr = Array.length arr |> Z.of_int
end
