module type G = Ortac_core.Config_intf.S

module M : G = struct
  open Ppxlib

  include Ast_builder.Make (struct
    let loc = Location.none
  end)

  let open_modules = [%stri open Ortac_runtime]

  let report_pre acc_name =
    [%expr Errors.check_and_do Errors.report_and_raise [%e evar acc_name]]

  let report_post acc_name =
    [%expr Errors.check_and_do Errors.report_and_raise [%e evar acc_name]]

  let report_declared_exn acc_name alias =
    [%expr
      Errors.check_and_do Errors.report_and_raise [%e evar acc_name];
      raise [%e evar alias]]

  let report_undeclared_exn eloc fun_name acc_name =
    [%expr
      let err = mk_unexpected_exception [%e eloc] [%e estring fun_name] e in
      Errors.register err [%e evar acc_name];
      Errors.report [%e evar acc_name];
      Errors.raise_errors [%e evar acc_name]]
end

module B = Ortac_core.Builder.Make (M)
module G = Ortac_core.Ortac.Make (M)

let tests module_name s =
  try
    let include_lib =
      B.pmod_ident (B.lident module_name) |> B.include_infos |> B.pstr_include
    in
    let declarations = G.signature s in
    B.mk_open :: include_lib :: declarations
  with
  | B.Unsupported (_loc, msg) ->
      let open Fmt in
      failwith "%a: unsupported %s" (styled `Red string) "Error" msg
  | e -> raise e

let generate path =
  let module_name = Ortac_core.Utils.module_name_of_path path in
  Gospel.Parser_frontend.parse_ocaml_gospel path
  |> Ortac_core.Utils.type_check [] path
  |> tests module_name
  |> Ppxlib_ast.Pprintast.structure Fmt.stdout
