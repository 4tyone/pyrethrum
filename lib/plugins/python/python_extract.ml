open Python_ast
module A = Pyrethrum.Ast

type binding = {
  var_name : string;
  func_name : string;
  loc : Python_ast.loc;
  call_index : int;
}

type call_record = {
  call_func_name : string;
  call_loc : Python_ast.loc;
  call_var_name : string option;
  mutable call_handled : bool;
}

type extraction_state = {
  mutable signatures : A.func_signature list;
  mutable matches : A.match_call list;
  mutable bindings : binding list;
  mutable calls : call_record list;
  mutable known_decorated : string list;
  source_file : string;
  mutable current_class : string option;
}

let make_state source_file = {
  signatures = [];
  matches = [];
  bindings = [];
  calls = [];
  known_decorated = [];
  source_file;
  current_class = None;
}

let py_loc_to_ast_loc file (loc : Python_ast.loc) : A.loc = {
  A.file;
  line = loc.lineno;
  col = loc.col_offset;
  end_line = loc.end_lineno;
  end_col = loc.end_col_offset;
}

let rec expr_to_name = function
  | Name { id; _ } -> Some id
  | Attribute { value; attr; _ } -> (
    match expr_to_name value with
    | Some base -> Some (base ^ "." ^ attr)
    | None -> Some attr)
  | _ -> None

let expr_to_exc_type expr : A.exc_type option =
  match expr with
  | Name { id; _ } -> Some (A.ExcName id)
  | Attribute { value; attr; _ } -> (
    match expr_to_name value with
    | Some module_ -> Some (A.ExcQualified (module_, attr))
    | None -> Some (A.ExcName attr))
  | _ -> None

let is_raises_decorator expr =
  match expr with
  | Name { id; _ } -> id = "raises" || id = "async_raises"
  | Call { func = Name { id; _ }; _ } -> id = "raises" || id = "async_raises"
  | _ -> false

let is_returns_option_decorator expr =
  match expr with
  | Name { id; _ } -> id = "returns_option"
  | Call { func = Name { id; _ }; _ } -> id = "returns_option"
  | _ -> false

let extract_raises_args expr : A.exc_type list =
  match expr with
  | Call { args; _ } ->
    List.filter_map expr_to_exc_type args
  | _ -> []

let extract_func_signature state name is_async decorator_list loc =
  let raises_decorator = List.find_opt is_raises_decorator decorator_list in
  let option_decorator = List.find_opt is_returns_option_decorator decorator_list in
  match raises_decorator, option_decorator with
  | Some dec, _ ->
    let exceptions = extract_raises_args dec in
    let qualified_name = match state.current_class with
      | Some cls -> Some (cls ^ "." ^ name)
      | None -> None
    in
    let sig_ : A.func_signature = {
      name;
      qualified_name;
      declared_exceptions = exceptions;
      loc = py_loc_to_ast_loc state.source_file loc;
      is_async;
      signature_type = A.SigRaises;
    } in
    state.signatures <- sig_ :: state.signatures;
    state.known_decorated <- name :: state.known_decorated
  | None, Some _ ->
    let qualified_name = match state.current_class with
      | Some cls -> Some (cls ^ "." ^ name)
      | None -> None
    in
    let sig_ : A.func_signature = {
      name;
      qualified_name;
      declared_exceptions = [];
      loc = py_loc_to_ast_loc state.source_file loc;
      is_async;
      signature_type = A.SigOption;
    } in
    state.signatures <- sig_ :: state.signatures;
    state.known_decorated <- name :: state.known_decorated
  | None, None -> ()

let is_ok_pattern pattern =
  match pattern with
  | MatchClass { cls = Name { id = "Ok"; _ }; _ } -> true
  | MatchAs { pattern = Some (MatchClass { cls = Name { id = "Ok"; _ }; _ }); _ } -> true
  | _ -> false

let is_some_pattern pattern =
  match pattern with
  | MatchClass { cls = Name { id = "Some"; _ }; _ } -> true
  | MatchAs { pattern = Some (MatchClass { cls = Name { id = "Some"; _ }; _ }); _ } -> true
  | _ -> false

let is_nothing_pattern pattern =
  match pattern with
  | MatchClass { cls = Name { id = "Nothing"; _ }; _ } -> true
  | MatchAs { pattern = Some (MatchClass { cls = Name { id = "Nothing"; _ }; _ }); _ } -> true
  | _ -> false

let is_err_pattern pattern =
  match pattern with
  | MatchClass { cls = Name { id = "Err"; _ }; patterns; _ } -> Some patterns
  | MatchAs { pattern = Some (MatchClass { cls = Name { id = "Err"; _ }; patterns; _ }); _ } -> Some patterns
  | _ -> None

let rec extract_exception_from_pattern pattern : A.exc_type option =
  match pattern with
  | MatchClass { cls; _ } -> expr_to_exc_type cls
  | MatchAs { pattern = Some inner; _ } -> extract_exception_from_pattern inner
  | _ -> None

let extract_handlers_from_cases cases : A.exc_type list * bool * bool * bool =
  let handlers = ref [] in
  let has_ok = ref false in
  let has_some = ref false in
  let has_nothing = ref false in
  List.iter (fun case ->
    if is_ok_pattern case.pattern then has_ok := true
    else if is_some_pattern case.pattern then has_some := true
    else if is_nothing_pattern case.pattern then has_nothing := true
    else match is_err_pattern case.pattern with
      | Some inner_patterns ->
        List.iter (fun p ->
          match extract_exception_from_pattern p with
          | Some exc -> handlers := exc :: !handlers
          | None -> ()
        ) inner_patterns
      | None -> ()
  ) cases;
  (List.rev !handlers, !has_ok, !has_some, !has_nothing)

let extract_handlers_from_dict_call args : A.exc_type list * bool * bool * bool =
  let handlers = ref [] in
  let has_ok = ref false in
  let has_some = ref false in
  let has_nothing = ref false in
  List.iter (fun arg ->
    match arg with
    | Dict { keys; _ } ->
      List.iter (fun key_opt ->
        match key_opt with
        | Some (Name { id = "Ok"; _ }) -> has_ok := true
        | Some (Name { id = "Some"; _ }) -> has_some := true
        | Some (Name { id = "Nothing"; _ }) -> has_nothing := true
        | Some expr ->
          (match expr_to_exc_type expr with
           | Some exc -> handlers := exc :: !handlers
           | None -> ())
        | None -> ()
      ) keys
    | _ -> ()
  ) args;
  (List.rev !handlers, !has_ok, !has_some, !has_nothing)

let is_match_function_call expr =
  match expr with
  | Call { func = Name { id = "match"; _ }; args; _ } when List.length args >= 1 -> true
  | Call { func = Name { id = "async_match"; _ }; args; _ } when List.length args >= 1 -> true
  | _ -> false

let get_match_target_func expr =
  match expr with
  | Call { func = Name { id = ("match" | "async_match"); _ }; args; _ } -> (
    match args with
    | first :: _ -> expr_to_name first
    | [] -> None)
  | _ -> None

let mark_call_handled_by_var state var_name =
  match List.find_opt (fun b -> b.var_name = var_name) state.bindings with
  | Some binding ->
    List.iteri (fun i call ->
      if i = binding.call_index then
        call.call_handled <- true
    ) (List.rev state.calls)
  | None -> ()

let rec extract_from_expr state expr =
  match expr with
  | Call { func; args; keywords; loc } ->
    extract_from_expr state func;
    List.iter (extract_from_expr state) args;
    List.iter (fun kw -> extract_from_expr state kw.value) keywords;

    (* match(func, args) calls the function internally, no separate call to mark *)

    (match expr_to_name func with
     | Some name when List.mem name state.known_decorated ->
       let call : call_record = {
         call_func_name = name;
         call_loc = loc;
         call_var_name = None;
         call_handled = false;
       } in
       state.calls <- call :: state.calls
     | _ -> ())
  | Attribute { value; _ } -> extract_from_expr state value
  | Subscript { value; slice; _ } ->
    extract_from_expr state value;
    extract_from_expr state slice
  | BinOp { left; right; _ } ->
    extract_from_expr state left;
    extract_from_expr state right
  | Tuple { elts; _ } | List { elts; _ } | BoolOp { values = elts; _ } | JoinedStr { values = elts; _ } ->
    List.iter (extract_from_expr state) elts
  | Dict { keys; values; _ } ->
    List.iter (function Some k -> extract_from_expr state k | None -> ()) keys;
    List.iter (extract_from_expr state) values
  | IfExp { test; body; orelse; _ } ->
    extract_from_expr state test;
    extract_from_expr state body;
    extract_from_expr state orelse
  | Lambda { body; _ } -> extract_from_expr state body
  | UnaryOp { operand; _ } -> extract_from_expr state operand
  | Compare { left; comparators; _ } ->
    extract_from_expr state left;
    List.iter (extract_from_expr state) comparators
  | Starred { value; _ } | Await { value; _ } | YieldFrom { value; _ } | FormattedValue { value; _ } ->
    extract_from_expr state value
  | Yield { value; _ } -> Option.iter (extract_from_expr state) value
  | NamedExpr { target; value; _ } ->
    extract_from_expr state target;
    extract_from_expr state value
  | Slice { lower; upper; step; _ } ->
    Option.iter (extract_from_expr state) lower;
    Option.iter (extract_from_expr state) upper;
    Option.iter (extract_from_expr state) step
  | Name _ | Constant _ | UnknownExpr _ -> ()

let extract_match_call_from_expr state outer_expr =
  (* Pattern: match(func, args)({Ok: ..., Err: ...}) *)
  match outer_expr with
  | Call { func = inner_call; args = dict_args; loc; _ } when is_match_function_call inner_call ->
    (match get_match_target_func inner_call with
     | Some func_name ->
       let handlers, has_ok, has_some, has_nothing = extract_handlers_from_dict_call dict_args in
       let match_call : A.match_call = {
         func_name;
         handlers;
         has_ok_handler = has_ok;
         has_some_handler = has_some;
         has_nothing_handler = has_nothing;
         loc = py_loc_to_ast_loc state.source_file loc;
         kind = A.MatchFunctionCall;
       } in
       state.matches <- match_call :: state.matches
       (* match(func, args) calls the function internally, no separate call to mark *)
     | None -> ())
  | _ -> ()

let rec extract_from_stmt state stmt =
  match stmt with
  | FunctionDef { name; args = _; body; decorator_list; is_async; loc; _ } ->
    extract_func_signature state name is_async decorator_list loc;
    List.iter (extract_from_stmt state) body
  | ClassDef { name; body; decorator_list; _ } ->
    List.iter (extract_from_expr state) decorator_list;
    let old_class = state.current_class in
    state.current_class <- Some name;
    List.iter (extract_from_stmt state) body;
    state.current_class <- old_class
  | Assign { targets; value; loc } ->
    extract_from_expr state value;

    (* Track variable bindings to decorated function calls *)
    (match value with
     | Call { func; _ } ->
       (match expr_to_name func with
        | Some func_name when List.mem func_name state.known_decorated ->
          List.iter (fun target ->
            match target with
            | Name { id = var_name; _ } ->
              let call_index = List.length state.calls - 1 in
              let binding : binding = { var_name; func_name; loc; call_index } in
              state.bindings <- binding :: state.bindings
            | _ -> ()
          ) targets
        | _ -> ())
     | _ -> ());

    (* Check for match()({...}) call *)
    extract_match_call_from_expr state value
  | AnnAssign { target; annotation; value; _ } ->
    extract_from_expr state target;
    extract_from_expr state annotation;
    Option.iter (extract_from_expr state) value;
    Option.iter (extract_match_call_from_expr state) value
  | Match { subject; cases; loc } ->
    extract_from_expr state subject;
    List.iter (fun case -> List.iter (extract_from_stmt state) case.case_body) cases;

    (* Find which function this match is for and mark the call as handled *)
    let func_name, var_to_mark = match subject with
      | Name { id; _ } ->
        (* Find binding for this variable *)
        let binding = List.find_opt (fun b -> b.var_name = id) state.bindings in
        (Option.map (fun b -> b.func_name) binding, Some id)
      | Call { func; _ } ->
        (* Direct call as match subject - the call was just added, mark the latest *)
        let fn = expr_to_name func in
        (fn, None)
      | _ -> (None, None)
    in
    (match func_name with
     | Some fn ->
       let handlers, has_ok, has_some, has_nothing = extract_handlers_from_cases cases in
       let match_call : A.match_call = {
         func_name = fn;
         handlers;
         has_ok_handler = has_ok;
         has_some_handler = has_some;
         has_nothing_handler = has_nothing;
         loc = py_loc_to_ast_loc state.source_file loc;
         kind = A.MatchStatement;
       } in
       state.matches <- match_call :: state.matches;
       (* Mark the specific call as handled *)
       (match var_to_mark with
        | Some var_name -> mark_call_handled_by_var state var_name
        | None ->
          (* Direct call - mark the most recent call to this function *)
          match List.find_opt (fun c -> c.call_func_name = fn) state.calls with
          | Some call -> call.call_handled <- true
          | None -> ())
     | None -> ())
  | Return { value; _ } ->
    Option.iter (extract_from_expr state) value;
    Option.iter (extract_match_call_from_expr state) value
  | Expr { value; _ } ->
    extract_from_expr state value;
    extract_match_call_from_expr state value
  | If { test; body; orelse; _ } ->
    extract_from_expr state test;
    List.iter (extract_from_stmt state) body;
    List.iter (extract_from_stmt state) orelse
  | For { target; iter; body; orelse; _ } | AsyncFor { target; iter; body; orelse; _ } ->
    extract_from_expr state target;
    extract_from_expr state iter;
    List.iter (extract_from_stmt state) body;
    List.iter (extract_from_stmt state) orelse
  | While { test; body; orelse; _ } ->
    extract_from_expr state test;
    List.iter (extract_from_stmt state) body;
    List.iter (extract_from_stmt state) orelse
  | With { items; body; _ } | AsyncWith { items; body; _ } ->
    List.iter (fun item ->
      extract_from_expr state item.context_expr;
      Option.iter (extract_from_expr state) item.optional_vars
    ) items;
    List.iter (extract_from_stmt state) body
  | Try { body; handlers; orelse; finalbody; _ } | TryStar { body; handlers; orelse; finalbody; _ } ->
    List.iter (extract_from_stmt state) body;
    List.iter (fun h ->
      Option.iter (extract_from_expr state) h.type_;
      List.iter (extract_from_stmt state) h.handler_body
    ) handlers;
    List.iter (extract_from_stmt state) orelse;
    List.iter (extract_from_stmt state) finalbody
  | Raise { exc; cause; _ } ->
    Option.iter (extract_from_expr state) exc;
    Option.iter (extract_from_expr state) cause
  | AugAssign { target; value; _ } ->
    extract_from_expr state target;
    extract_from_expr state value
  | Assert { test; msg; _ } ->
    extract_from_expr state test;
    Option.iter (extract_from_expr state) msg
  | Delete { targets; _ } ->
    List.iter (extract_from_expr state) targets
  | Import _ | ImportFrom _ | Global _ | Nonlocal _ | Pass _ | Break _ | Continue _ | UnknownStmt _ -> ()

let get_unhandled_calls state : A.unhandled_call list =
  state.calls
  |> List.filter (fun call -> not call.call_handled)
  |> List.map (fun call ->
    let sig_opt = List.find_opt (fun (s : A.func_signature) -> s.name = call.call_func_name) state.signatures in
    let signature_type = match sig_opt with
      | Some s -> s.signature_type
      | None -> A.SigRaises
    in
    { A.func_name = call.call_func_name;
      loc = py_loc_to_ast_loc state.source_file call.call_loc;
      signature_type })

let extract_from_module source_file (module_ : Python_ast.module_) : A.analysis_input =
  let state = make_state source_file in

  (* First pass: collect all decorated functions *)
  List.iter (extract_from_stmt state) module_.body;

  (* Get unhandled calls *)
  let unhandled_calls = get_unhandled_calls state in

  { A.language = A.Python;
    signatures = List.rev state.signatures;
    matches = List.rev state.matches;
    unhandled_calls }
