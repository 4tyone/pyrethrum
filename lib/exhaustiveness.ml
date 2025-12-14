open Ast

type error =
  | MissingHandlers of { func_name : string; missing : exc_type list; loc : loc }
  | ExtraHandlers of { func_name : string; extra : exc_type list; loc : loc }
  | MissingOkHandler of { func_name : string; loc : loc }
  | MissingSomeHandler of { func_name : string; loc : loc }
  | MissingNothingHandler of { func_name : string; loc : loc }
  | UnknownFunction of { name : string; loc : loc }
  | UnhandledResult of { func_name : string; loc : loc }
  | UnhandledOption of { func_name : string; loc : loc }
[@@deriving show, eq]

let check_raises_signature (signature : func_signature) (call : match_call) : error list =
  let required =
    ExcSet.of_list (ExcOk :: signature.declared_exceptions)
  in
  let provided_list =
    if call.has_ok_handler then ExcOk :: call.handlers else call.handlers
  in
  let provided = ExcSet.of_list provided_list in
  let missing = ExcSet.diff required provided in
  let extra = ExcSet.diff provided required in
  let errors = [] in
  let errors =
    if (not call.has_ok_handler) && ExcSet.mem ExcOk required then
      MissingOkHandler { func_name = call.func_name; loc = call.loc } :: errors
    else errors
  in
  let errors =
    let missing_list = ExcSet.elements missing |> List.filter (fun e -> e <> ExcOk) in
    if missing_list <> [] then
      MissingHandlers { func_name = call.func_name; missing = missing_list; loc = call.loc }
      :: errors
    else errors
  in
  let errors =
    let extra_list = ExcSet.elements extra in
    if extra_list <> [] then
      ExtraHandlers { func_name = call.func_name; extra = extra_list; loc = call.loc } :: errors
    else errors
  in
  errors

let check_option_signature (call : match_call) : error list =
  let errors = [] in
  let errors =
    if not call.has_some_handler then
      MissingSomeHandler { func_name = call.func_name; loc = call.loc } :: errors
    else errors
  in
  let errors =
    if not call.has_nothing_handler then
      MissingNothingHandler { func_name = call.func_name; loc = call.loc } :: errors
    else errors
  in
  (* Check for extra handlers - Option types only allow Some and Nothing *)
  let errors =
    if call.handlers <> [] then
      ExtraHandlers { func_name = call.func_name; extra = call.handlers; loc = call.loc } :: errors
    else errors
  in
  errors

let check_one (signatures : func_signature StringMap.t) (call : match_call) : error list =
  match StringMap.find_opt call.func_name signatures with
  | None -> [ UnknownFunction { name = call.func_name; loc = call.loc } ]
  | Some signature ->
      match signature.signature_type with
      | SigRaises -> check_raises_signature signature call
      | SigOption -> check_option_signature call

let check_unhandled (unhandled : unhandled_call) : error =
  match unhandled.signature_type with
  | SigRaises -> UnhandledResult { func_name = unhandled.func_name; loc = unhandled.loc }
  | SigOption -> UnhandledOption { func_name = unhandled.func_name; loc = unhandled.loc }

let check_all (signatures : func_signature list) (calls : match_call list) : error list =
  let sig_map =
    List.fold_left
      (fun acc sig_ -> StringMap.add sig_.name sig_ acc)
      StringMap.empty signatures
  in
  List.concat_map (check_one sig_map) calls

let check_all_with_unhandled (signatures : func_signature list) (calls : match_call list) (unhandled_calls : unhandled_call list) : error list =
  let sig_map =
    List.fold_left
      (fun acc sig_ -> StringMap.add sig_.name sig_ acc)
      StringMap.empty signatures
  in
  let match_errors = List.concat_map (check_one sig_map) calls in
  let unhandled_errors = List.map check_unhandled unhandled_calls in
  match_errors @ unhandled_errors
