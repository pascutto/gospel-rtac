open Ppxlib
open Gospel
open Fmt
open Builder
module F = Failure

exception Unsupported of Location.t option * string

let rec pattern p =
  match p.Tterm.p_node with
  | Tterm.Pwild -> ppat_any
  | Tterm.Pvar v -> pvar (str "%a" Identifier.Ident.pp v.vs_name)
  | Tterm.Papp (l, pl) when Tterm.is_fs_tuple l ->
      ppat_tuple (List.map pattern pl)
  | Tterm.Papp (l, pl) ->
      let args =
        if pl = [] then None else Some (ppat_tuple (List.map pattern pl))
      in
      ppat_construct (lident l.ls_name.id_str) args
  | Tterm.Por (p1, p2) -> ppat_or (pattern p1) (pattern p2)
  | Tterm.Pas (p, v) ->
      ppat_alias (pattern p) (noloc (str "%a" Identifier.Ident.pp v.vs_name))

let rec array_no_coercion ?typ (ls : Tterm.lsymbol) (tlist : Tterm.term list) =
  let term = term ?typ in
  (match ls.ls_name.id_str with
  | "mixfix [_]" -> Some "Array.get"
  | "length" -> Some "Array.length"
  | _ -> None)
  |> Option.map (fun f ->
         match (List.hd tlist).t_node with
         | Tapp (elts, [ arr ]) when elts.ls_name.id_str = "elts" ->
             Some (eapply (evar f) (term arr :: List.map term (List.tl tlist)))
         | _ -> None)
  |> Option.join

and bounds ?typ (var : Tterm.vsymbol) (t : Tterm.term) :
    (expression * expression) option =
  let term = term ?typ in
  (* [comb] extracts a bound from an the operator [f] and expression [e].
     [right] indicates if [e] is on the right side of the operator. *)
  let comb ~right (f : Tterm.lsymbol) e =
    match f.ls_name.id_str with
    | "infix >=" -> if right then (Some e, None) else (None, Some e)
    | "infix <=" -> if right then (None, Some e) else (Some e, None)
    | "infix <" ->
        if right then (None, Some (epred e)) else (Some (esucc e), None)
    | "infix >" ->
        if right then (Some (esucc e), None) else (None, Some (epred e))
    | _ -> (None, None)
  in
  let bound = function
    | Tterm.Tapp (f, [ x1; x2 ]) -> (
        match (x1, x2) with
        | { Tterm.t_node = Tvar { vs_name; _ }; _ }, _
          when vs_name = var.vs_name ->
            let e2 = term x2 in
            comb ~right:true f e2
        | _, { Tterm.t_node = Tvar { vs_name; _ }; _ }
          when vs_name = var.vs_name ->
            let e1 = term x1 in
            comb ~right:false f e1
        | _, _ -> (None, None))
    | _ -> (None, None)
  in
  match t.t_node with
  | Tbinop (Tand, t1, t2) -> (
      match (bound t1.t_node, bound t2.t_node) with
      | (None, Some eupper), (Some elower, None)
      | (Some elower, None), (None, Some eupper) ->
          Some (elower, eupper)
      | _, _ -> None
      | exception Unsupported _ -> None)
  | _ -> None

and term ?typ (t : Tterm.term) : expression =
  let term = term ?typ in
  let unsupported m = raise (Unsupported (t.t_loc, m)) in
  match t.t_node with
  | Tvar { vs_name; _ } -> evar (str "%a" Identifier.Ident.pp vs_name)
  | Tconst c -> econst c
  | Tfield (t, f) -> pexp_field (term t) (lident f.ls_name.id_str)
  | Tapp (fs, []) when fs.ls_field -> (
      match typ with
      | Some t -> pexp_field (evar t) (lident fs.ls_name.id_str)
      | None ->
          Fmt.failwith
            "no type variable was provided in type field translation: `%s'"
            fs.ls_name.id_str)
  | Tapp (fs, []) when Tterm.(ls_equal fs fs_bool_true) -> [%expr true]
  | Tapp (fs, []) when Tterm.(ls_equal fs fs_bool_false) -> [%expr false]
  | Tapp (fs, tlist) when Tterm.is_fs_tuple fs ->
      List.map term tlist |> pexp_tuple
  | Tapp (ls, tlist) -> (
      match array_no_coercion ?typ ls tlist with
      | Some e -> e
      | None -> (
          let func = ls.ls_name.id_str in
          Drv.find_opt func |> function
          | Some f -> eapply (evar f) (List.map term tlist)
          | None ->
              if ls.ls_constr then
                (if tlist = [] then None
                else Some (List.map term tlist |> pexp_tuple))
                |> pexp_construct (lident func)
              else kstr unsupported "function application `%s`" func))
  | Tif (i, t, e) -> [%expr if [%e term i] then [%e term t] else [%e term e]]
  | Tlet (x, t1, t2) ->
      let x = str "%a" Identifier.Ident.pp x.vs_name in
      [%expr
        let [%p pvar x] = [%e term t1] in
        [%e term t2]]
  | Tcase (t, ptl) ->
      List.map
        (fun (p, t) -> case ~guard:None ~lhs:(pattern p) ~rhs:(term t))
        ptl
      |> pexp_match (term t)
  | Tquant (quant, [ var ], _, t) -> (
      match quant with
      | Tterm.Tforall | Tterm.Texists -> (
          let z_op = if quant = Tforall then "forall" else "exists" in
          let gospel_op = function
            | Tterm.Timplies -> quant = Tforall
            | Tterm.Tand | Tand_asym -> quant = Texists
            | _ -> false
          in
          match t.t_node with
          | Tbinop (op, t1, t2) when gospel_op op -> (
              bounds ?typ var t1 |> function
              | None -> unsupported "forall/exists"
              | Some (start, stop) ->
                  let t2 = term t2 in
                  let x = str "%a" Identifier.Ident.pp var.vs_name in
                  let func = pexp_fun Nolabel None (pvar x) t2 in
                  eapply (evar (str "Z.%s" z_op)) [ start; stop; func ])
          | Tterm.Ttrue -> [%expr true]
          | Tterm.Tfalse -> [%expr false]
          | _ -> unsupported z_op)
      | Tterm.Tlambda -> unsupported "lambda quantification")
  | Tquant (_, _, _, _) -> unsupported "forall/exists with multiple variables"
  | Tbinop (op, t1, t2) -> (
      match op with
      | Tterm.Tand ->
          let vt1 = gen_symbol ~prefix:"__t1" () in
          let vt2 = gen_symbol ~prefix:"__t2" () in
          [%expr
            let [%p pvar vt1] = [%e term t1] in
            let [%p pvar vt2] = [%e term t2] in
            [%e evar vt1] && [%e evar vt2]]
      | Tterm.Tand_asym -> [%expr [%e term t1] && [%e term t2]]
      | Tterm.Tor ->
          let vt1 = gen_symbol ~prefix:"__t1" () in
          let vt2 = gen_symbol ~prefix:"__t2" () in
          [%expr
            let [%p pvar vt1] = [%e term t1] in
            let [%p pvar vt2] = [%e term t2] in
            [%e evar vt1] || [%e evar vt2]]
      | Tterm.Tor_asym -> [%expr [%e term t1] || [%e term t2]]
      | Tterm.Timplies -> [%expr (not [%e term t1]) || [%e term t2]]
      | Tterm.Tiff -> [%expr [%e term t1] = [%e term t2]])
  | Tnot t -> [%expr not [%e term t]]
  | Told _ -> unsupported "old operator"
  | Ttrue -> [%expr true]
  | Tfalse -> [%expr false]

let term ?typ fail t =
  [%expr
    try [%e term ?typ t]
    with e ->
      [%e fail (evar "e")];
      true]

let conditions ~term_printer fail_violated fail_nonexec terms =
  List.map
    (fun t ->
      let s = term_printer t in
      [%expr if not [%e term (fail_nonexec s) t] then [%e fail_violated s]])
    terms
  |> esequence

let post ~register_name ~term_printer =
  let fail_violated term = F.violated `Post ~term ~register_name in
  let fail_nonexec term exn = F.spec_failure `Post ~term ~exn ~register_name in
  conditions ~term_printer fail_violated fail_nonexec

let pre ~register_name ~term_printer =
  let fail_violated term = F.violated `Pre ~term ~register_name in
  let fail_nonexec term exn = F.spec_failure `Pre ~term ~exn ~register_name in
  conditions ~term_printer fail_violated fail_nonexec

let invariant ~state ~typ ~register_name ~term_printer terms =
  let fail_violated term =
    F.violated_invariant ~state ~typ ~term ~register_name
  in
  let fail_nonexec term exn =
    F.spec_failure `Invariant ~term ~exn ~register_name
  in
  List.map
    (fun t ->
      let s = term_printer t in
      [%expr if not [%e term ~typ (fail_nonexec s) t] then [%e fail_violated s]])
    terms
  |> esequence

let rec xpost_pattern exn = function
  | Tterm.Pwild -> ppat_construct (lident exn) (Some ppat_any)
  | Tterm.Pvar x ->
      ppat_construct (lident exn)
        (Some (ppat_var (noloc (str "%a" Tterm.Ident.pp x.vs_name))))
  | Tterm.Papp (ls, []) when Tterm.(ls_equal ls (fs_tuple 0)) -> pvar exn
  | Tterm.Papp (_ls, _l) -> assert false
  | Tterm.Por (p1, p2) ->
      ppat_or (xpost_pattern exn p1.p_node) (xpost_pattern exn p2.p_node)
  | Tterm.Pas (p, s) ->
      ppat_alias
        (xpost_pattern exn p.p_node)
        (noloc (str "%a" Tterm.Ident.pp s.vs_name))

let xpost_guard ~register_name ~term_printer xpost call input_invariants
    check_checks checks =
  let module M = Map.Make (struct
    type t = Ttypes.xsymbol

    let compare = compare
  end) in
  let default_cases =
    let d =
      [
        case ~guard:None
          ~lhs:[%pat? (Stack_overflow | Out_of_memory) as e]
          ~rhs:
            [%expr
              [%e
                check_checks ~negative:false
                @@ input_invariants @@ F.report ~register_name];
              raise e];
        case ~guard:None
          ~lhs:[%pat? e]
          ~rhs:
            [%expr
              [%e
                F.unexpected_exn ~allowed_exn:[] ~exn:(evar "e") ~register_name];
              [%e
                check_checks ~negative:false
                @@ input_invariants @@ F.report ~register_name];
              raise e];
      ]
    in
    if checks then
      case ~guard:None
        ~lhs:[%pat? Invalid_argument _ as e]
        ~rhs:(check_checks ~negative:true @@ eapply (evar "raise") [ evar "e" ])
      :: d
    else d
  in
  let assert_false_case =
    case ~guard:None ~lhs:[%pat? _] ~rhs:[%expr assert false]
  in
  List.fold_left
    (fun map (exn, ptlist) ->
      let name = exn.Ttypes.xs_ident.id_str in
      let cases =
        List.rev_map
          (fun (p, t) ->
            let s = term_printer t in
            let fail_nonexec exn =
              F.spec_failure `XPost ~term:s ~exn ~register_name
            in
            case ~guard:None
              ~lhs:(xpost_pattern name p.Tterm.p_node)
              ~rhs:
                [%expr
                  if not [%e term fail_nonexec t] then
                    [%e F.violated `XPost ~term:s ~register_name]])
          ptlist
        @ [ assert_false_case ]
      in
      M.update exn
        (function None -> Some [ cases ] | Some e -> Some (cases :: e))
        map)
    M.empty xpost
  |> fun cases ->
  M.fold
    (fun exn cases acc ->
      let name = exn.Ttypes.xs_ident.id_str in
      let has_args = exn.Ttypes.xs_type <> Ttypes.Exn_tuple [] in
      let alias = gen_symbol ~prefix:"__e" () in
      let rhs =
        input_invariants
        @@ [%expr
             [%e List.map (pexp_match (evar alias)) cases |> esequence];
             [%e F.report ~register_name];
             raise [%e evar alias]]
      in
      let lhs =
        ppat_alias
          (ppat_construct (lident name)
             (if has_args then Some ppat_any else None))
          (noloc alias)
      in
      case ~guard:None ~lhs ~rhs :: acc)
    cases default_cases
  |> pexp_try call

let returned_pattern rets =
  let to_string x = str "%a" Tast.Ident.pp x.Tterm.vs_name in
  let pvars, evars =
    List.filter_map
      (function
        | Tast.Lunit -> Some (punit, eunit)
        | Tast.Lnone x ->
            let s = to_string x in
            Some (pvar s, evar s)
        | Tast.Lghost _ -> None
        | Tast.Loptional _ | Tast.Lnamed _ -> assert false)
      rets
    |> List.split
  in
  (ppat_tuple pvars, pexp_tuple evars)

let mk_setup loc fun_name =
  let loc_name = gen_symbol ~prefix:"__loc" () in
  let let_loc next =
    [%expr
      let [%p pvar loc_name] = [%e elocation loc] in
      [%e next]]
  in
  let register_name = gen_symbol ~prefix:"__acc" () in
  let let_acc next =
    [%expr
      let [%p pvar register_name] =
        Errors.create [%e evar loc_name] [%e estring fun_name]
      in
      [%e next]]
  in
  ((fun next -> let_loc @@ let_acc @@ next), register_name)

let mk_pre_checks ~register_name ~term_printer pres next =
  [%expr
    [%e pre ~register_name ~term_printer pres];
    [%e F.report ~register_name];
    [%e next]]

let mk_call ~register_name ~term_printer ret_pat loc fun_name xpost eargs
    input_invariants check_checks checks =
  let call = pexp_apply (evar fun_name) eargs in
  let check_raises =
    xpost_guard ~register_name ~term_printer xpost call input_invariants
      check_checks checks
  in
  fun next ->
    [%expr
      let [%p ret_pat] = [%e check_raises] in
      [%e next]]

let mk_post_checks ~register_name ~term_printer posts next =
  [%expr
    [%e post ~register_name ~term_printer posts];
    [%e F.report ~register_name];
    [%e next]]

let mk_invariant_checks ~state ~typ ~register_name ~term_printer invariants =
  invariant ~state ~typ ~register_name ~term_printer invariants

let mk_checks_decl ~names ~register_name ~term_printer checks =
  let fail_nonexec term exn = F.spec_failure `Pre ~term ~exn ~register_name in
  fun next ->
    List.fold_left2
      (fun next check name ->
        let s = term_printer check in
        [%expr
          let [%p pvar name] = [%e term (fail_nonexec s) check] in
          [%e next]])
      next checks names

let mk_checks_checks ~negative ~names ~register_name ~term_printer checks =
  let fail_violated term = F.uncaught_checks ~register_name ~term in
  let fail_unexpected =
    F.unexpected_checks ~register_name ~terms:(List.map term_printer checks)
  in
  let checks_exprs =
    List.map2
      (fun name check ->
        let s = term_printer check in
        [%expr
          if [%e if negative then evar name else enot (evar name)] then
            [%e if negative then fail_unexpected else fail_violated s]])
      names checks
    |> esequence
  in
  fun next ->
    [%expr
      [%e checks_exprs];
      [%e F.report ~register_name];
      [%e next]]
