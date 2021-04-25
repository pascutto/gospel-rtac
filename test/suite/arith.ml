open Arith__Lib_rtac
open Common

let forall () =
  check_success "bounds in the right order" (fun () ->
      test_forall (-2) (-3) |> ignore);
  check_success "empty interval" (fun () -> test_forall (-2) (-2) |> ignore);
  check_raises_ortac "formula not satisfied" (fun () ->
      test_forall (-2) (-1) |> ignore);
  check_success "formula satisfied" (fun () -> test_forall 2 3 |> ignore)

let double_forall () =
  check_success "double forall" (fun () -> double_forall (-10) 10)

let power () =
  for i = 0 to 20 do
    check_success (Fmt.str "power 2 %i" i) (fun () -> power 2 i |> ignore)
  done;
  check_raises_ortac "power overflow" (fun () -> power 2 70 |> ignore)

let suite =
  ( "Arithmetics",
    [
      ("forall", `Quick, forall);
      ("power", `Quick, power);
      ("double forall", `Quick, double_forall);
    ] )
