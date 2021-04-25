let t =
  let t = Hashtbl.create 0 in
  List.iter
    (fun (gospel, ocaml) -> Hashtbl.add t gospel ocaml)
    [
      ("infix +", "Z.add");
      ("infix -", "Z.sub");
      ("infix *", "Z.mul");
      ("infix /", "Z.div");
      ("mod", "Z.rem");
      ("pow", "Z.pow");
      ("prefix -", "Z.neg");
      ("infix >", "Z.gt");
      ("infix >=", "Z.geq");
      ("infix <", "Z.lt");
      ("infix <=", "Z.leq");
      ("infix =", "(=)");
      ("integer_of_int", "Z.of_int");
      ("abs", "Z.abs");
      ("min", "Z.min");
      ("max", "Z.max");
      ("succ", "Z.succ");
      ("pred", "Z.pred");
    ];
  t

let find s = Hashtbl.find t s

let find_opt s = Hashtbl.find_opt t s
