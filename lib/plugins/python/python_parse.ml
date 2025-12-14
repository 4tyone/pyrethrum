open Python_ast

let ( let* ) = Result.bind
let ( >>= ) opt f = Option.bind opt f

let member key json =
  match json with
  | `Assoc fields -> (
    match List.assoc_opt key fields with
    | Some v -> Ok v
    | None -> Error (Printf.sprintf "Missing field: %s" key))
  | _ -> Error "Expected object"

let member_opt key json =
  match json with
  | `Assoc fields -> List.assoc_opt key fields
  | _ -> None

let to_string = function
  | `String s -> Ok s
  | `Null -> Ok ""
  | _ -> Error "Expected string"

let to_string_opt = function
  | `String s -> Some s
  | _ -> None

let to_int = function
  | `Int i -> Ok i
  | `Float f -> Ok (int_of_float f)
  | _ -> Error "Expected int"

let to_int_opt = function
  | `Int i -> Some i
  | `Float f -> Some (int_of_float f)
  | _ -> None

let to_bool = function
  | `Bool b -> Ok b
  | _ -> Error "Expected bool"

let to_list = function
  | `List l -> Ok l
  | _ -> Error "Expected list"

let to_list_opt = function
  | `List l -> Some l
  | _ -> None

let rec map_result f = function
  | [] -> Ok []
  | x :: xs ->
    let* y = f x in
    let* ys = map_result f xs in
    Ok (y :: ys)

let parse_loc json =
  let lineno = Option.bind (member_opt "lineno" json) to_int_opt |> Option.value ~default:0 in
  let col_offset = Option.bind (member_opt "col_offset" json) to_int_opt |> Option.value ~default:0 in
  let end_lineno = Option.bind (member_opt "end_lineno" json) to_int_opt |> Option.value ~default:lineno in
  let end_col_offset = Option.bind (member_opt "end_col_offset" json) to_int_opt |> Option.value ~default:col_offset in
  { lineno; col_offset; end_lineno; end_col_offset }

let get_type json =
  Option.bind (member_opt "_type" json) to_string_opt

let parse_constant_value json =
  match json with
  | `String s -> ConstString s
  | `Int _ -> ConstInt (match to_int json with Ok i -> i | _ -> 0)
  | `Float f -> ConstFloat f
  | `Bool b -> ConstBool b
  | `Null -> ConstNone
  | _ -> ConstOther

let rec parse_expr json : expr =
  let loc = parse_loc json in
  match get_type json with
  | Some "Name" ->
    let id = member_opt "id" json >>= to_string_opt |> Option.value ~default:"" in
    Name { id; loc }
  | Some "Attribute" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let attr = member_opt "attr" json >>= to_string_opt |> Option.value ~default:"" in
    Attribute { value; attr; loc }
  | Some "Call" ->
    let func = member_opt "func" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let args = member_opt "args" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    let keywords = member_opt "keywords" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_keyword in
    Call { func; args; keywords; loc }
  | Some "Constant" ->
    let value = member_opt "value" json |> Option.map parse_constant_value |> Option.value ~default:ConstNone in
    Constant { value; loc }
  | Some "Subscript" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let slice = member_opt "slice" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Subscript { value; slice; loc }
  | Some "BinOp" ->
    let left = member_opt "left" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let right = member_opt "right" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    BinOp { left; right; loc }
  | Some "Tuple" ->
    let elts = member_opt "elts" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    Tuple { elts; loc }
  | Some "List" ->
    let elts = member_opt "elts" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    List { elts; loc }
  | Some "Dict" ->
    let keys = member_opt "keys" json >>= to_list_opt |> Option.value ~default:[] |> List.map (fun k -> if k = `Null then None else Some (parse_expr k)) in
    let values = member_opt "values" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    Dict { keys; values; loc }
  | Some "IfExp" ->
    let test = member_opt "test" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let body = member_opt "body" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let orelse = member_opt "orelse" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    IfExp { test; body; orelse; loc }
  | Some "Lambda" ->
    let body = member_opt "body" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Lambda { body; loc }
  | Some "UnaryOp" ->
    let operand = member_opt "operand" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    UnaryOp { operand; loc }
  | Some "Compare" ->
    let left = member_opt "left" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let comparators = member_opt "comparators" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    Compare { left; comparators; loc }
  | Some "BoolOp" ->
    let values = member_opt "values" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    BoolOp { values; loc }
  | Some "Starred" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Starred { value; loc }
  | Some "Await" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Await { value; loc }
  | Some "Yield" ->
    let value = member_opt "value" json |> Option.map parse_expr in
    Yield { value; loc }
  | Some "YieldFrom" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    YieldFrom { value; loc }
  | Some "JoinedStr" ->
    let values = member_opt "values" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    JoinedStr { values; loc }
  | Some "FormattedValue" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    FormattedValue { value; loc }
  | Some "NamedExpr" ->
    let target = member_opt "target" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    NamedExpr { target; value; loc }
  | Some "Slice" ->
    let lower = member_opt "lower" json |> Option.map parse_expr in
    let upper = member_opt "upper" json |> Option.map parse_expr in
    let step = member_opt "step" json |> Option.map parse_expr in
    Slice { lower; upper; step; loc }
  | _ -> UnknownExpr { loc }

and parse_keyword json =
  let arg = member_opt "arg" json >>= to_string_opt in
  let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc = dummy_loc }) in
  { arg; value }

let rec parse_pattern json : pattern =
  let loc = parse_loc json in
  match get_type json with
  | Some "MatchValue" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    MatchValue { value; loc }
  | Some "MatchSingleton" ->
    let value = member_opt "value" json |> Option.map parse_constant_value |> Option.value ~default:ConstNone in
    MatchSingleton { value; loc }
  | Some "MatchSequence" ->
    let patterns = member_opt "patterns" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_pattern in
    MatchSequence { patterns; loc }
  | Some "MatchMapping" ->
    let keys = member_opt "keys" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    let patterns = member_opt "patterns" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_pattern in
    MatchMapping { keys; patterns; loc }
  | Some "MatchClass" ->
    let cls = member_opt "cls" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let patterns = member_opt "patterns" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_pattern in
    let kwd_patterns = member_opt "kwd_patterns" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_pattern in
    MatchClass { cls; patterns; kwd_patterns; loc }
  | Some "MatchStar" ->
    let name = member_opt "name" json >>= to_string_opt in
    MatchStar { name; loc }
  | Some "MatchAs" ->
    let pattern = member_opt "pattern" json |> Option.map parse_pattern in
    let name = member_opt "name" json >>= to_string_opt in
    MatchAs { pattern; name; loc }
  | Some "MatchOr" ->
    let patterns = member_opt "patterns" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_pattern in
    MatchOr { patterns; loc }
  | _ -> UnknownPattern { loc }

and parse_match_case json =
  let pattern = member_opt "pattern" json |> Option.map parse_pattern |> Option.value ~default:(UnknownPattern { loc = dummy_loc }) in
  let guard = member_opt "guard" json |> Option.map parse_expr in
  let case_body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
  { pattern; guard; case_body }

and parse_arg json =
  let arg_name = member_opt "arg" json >>= to_string_opt |> Option.value ~default:"" in
  let annotation = member_opt "annotation" json |> Option.map parse_expr in
  let arg_loc = parse_loc json in
  { arg_name; annotation; arg_loc }

and parse_arguments json =
  let posonlyargs = member_opt "posonlyargs" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_arg in
  let args = member_opt "args" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_arg in
  let vararg = member_opt "vararg" json |> Option.map parse_arg in
  let kwonlyargs = member_opt "kwonlyargs" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_arg in
  let kw_defaults = member_opt "kw_defaults" json >>= to_list_opt |> Option.value ~default:[] |> List.map (fun j -> if j = `Null then None else Some (parse_expr j)) in
  let kwarg = member_opt "kwarg" json |> Option.map parse_arg in
  let defaults = member_opt "defaults" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
  { posonlyargs; args; vararg; kwonlyargs; kw_defaults; kwarg; defaults }

and parse_withitem json =
  let context_expr = member_opt "context_expr" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc = dummy_loc }) in
  let optional_vars = member_opt "optional_vars" json |> Option.map parse_expr in
  { context_expr; optional_vars }

and parse_excepthandler json =
  let type_ = member_opt "type" json |> Option.map parse_expr in
  let name = member_opt "name" json >>= to_string_opt in
  let handler_body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
  let handler_loc = parse_loc json in
  { type_; name; handler_body; handler_loc }

and parse_alias json =
  let alias_name = member_opt "name" json >>= to_string_opt |> Option.value ~default:"" in
  let alias_asname = member_opt "asname" json >>= to_string_opt in
  { alias_name; alias_asname }

and parse_stmt json : stmt =
  let loc = parse_loc json in
  match get_type json with
  | Some "FunctionDef" | Some "AsyncFunctionDef" as t ->
    let is_async = t = Some "AsyncFunctionDef" in
    let name = member_opt "name" json >>= to_string_opt |> Option.value ~default:"" in
    let args = member_opt "args" json |> Option.map parse_arguments |> Option.value ~default:{ posonlyargs = []; args = []; vararg = None; kwonlyargs = []; kw_defaults = []; kwarg = None; defaults = [] } in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let decorator_list = member_opt "decorator_list" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    let returns = member_opt "returns" json |> Option.map parse_expr in
    FunctionDef { name; args; body; decorator_list; returns; is_async; loc }
  | Some "ClassDef" ->
    let name = member_opt "name" json >>= to_string_opt |> Option.value ~default:"" in
    let bases = member_opt "bases" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let decorator_list = member_opt "decorator_list" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    ClassDef { name; bases; body; decorator_list; loc }
  | Some "Return" ->
    let value = member_opt "value" json |> Option.map parse_expr in
    Return { value; loc }
  | Some "Assign" ->
    let targets = member_opt "targets" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Assign { targets; value; loc }
  | Some "AnnAssign" ->
    let target = member_opt "target" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let annotation = member_opt "annotation" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let value = member_opt "value" json |> Option.map parse_expr in
    AnnAssign { target; annotation; value; loc }
  | Some "AugAssign" ->
    let target = member_opt "target" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    AugAssign { target; value; loc }
  | Some "For" ->
    let target = member_opt "target" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let iter = member_opt "iter" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    For { target; iter; body; orelse; loc }
  | Some "AsyncFor" ->
    let target = member_opt "target" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let iter = member_opt "iter" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    AsyncFor { target; iter; body; orelse; loc }
  | Some "While" ->
    let test = member_opt "test" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    While { test; body; orelse; loc }
  | Some "If" ->
    let test = member_opt "test" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    If { test; body; orelse; loc }
  | Some "With" ->
    let items = member_opt "items" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_withitem in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    With { items; body; loc }
  | Some "AsyncWith" ->
    let items = member_opt "items" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_withitem in
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    AsyncWith { items; body; loc }
  | Some "Match" ->
    let subject = member_opt "subject" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let cases = member_opt "cases" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_match_case in
    Match { subject; cases; loc }
  | Some "Raise" ->
    let exc = member_opt "exc" json |> Option.map parse_expr in
    let cause = member_opt "cause" json |> Option.map parse_expr in
    Raise { exc; cause; loc }
  | Some "Try" ->
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let handlers = member_opt "handlers" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_excepthandler in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let finalbody = member_opt "finalbody" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    Try { body; handlers; orelse; finalbody; loc }
  | Some "TryStar" ->
    let body = member_opt "body" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let handlers = member_opt "handlers" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_excepthandler in
    let orelse = member_opt "orelse" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    let finalbody = member_opt "finalbody" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_stmt in
    TryStar { body; handlers; orelse; finalbody; loc }
  | Some "Assert" ->
    let test = member_opt "test" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    let msg = member_opt "msg" json |> Option.map parse_expr in
    Assert { test; msg; loc }
  | Some "Import" ->
    let names = member_opt "names" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_alias in
    Import { names; loc }
  | Some "ImportFrom" ->
    let module_ = member_opt "module" json >>= to_string_opt in
    let names = member_opt "names" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_alias in
    let level = member_opt "level" json >>= to_int_opt |> Option.value ~default:0 in
    ImportFrom { module_; names; level; loc }
  | Some "Global" ->
    let names = member_opt "names" json >>= to_list_opt |> Option.value ~default:[] |> List.filter_map to_string_opt in
    Global { names; loc }
  | Some "Nonlocal" ->
    let names = member_opt "names" json >>= to_list_opt |> Option.value ~default:[] |> List.filter_map to_string_opt in
    Nonlocal { names; loc }
  | Some "Expr" ->
    let value = member_opt "value" json |> Option.map parse_expr |> Option.value ~default:(UnknownExpr { loc }) in
    Expr { value; loc }
  | Some "Pass" -> Pass { loc }
  | Some "Break" -> Break { loc }
  | Some "Continue" -> Continue { loc }
  | Some "Delete" ->
    let targets = member_opt "targets" json >>= to_list_opt |> Option.value ~default:[] |> List.map parse_expr in
    Delete { targets; loc }
  | _ -> UnknownStmt { loc }

let parse_module json : (module_, string) result =
  let* body_json = member "body" json in
  let* body_list = to_list body_json in
  let body = List.map parse_stmt body_list in
  Ok { body; type_ignores = [] }
