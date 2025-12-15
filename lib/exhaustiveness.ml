open Ast

type error =
  | MissingHandlers of { func_name : string; missing : exc_type list; loc : loc; call_loc : loc option }
  | ExtraHandlers of { func_name : string; extra : exc_type list; loc : loc; call_loc : loc option }
  | MissingOkHandler of { func_name : string; loc : loc; call_loc : loc option }
  | MissingSomeHandler of { func_name : string; loc : loc; call_loc : loc option }
  | MissingNothingHandler of { func_name : string; loc : loc; call_loc : loc option }
  | UnknownFunction of { name : string; loc : loc; call_loc : loc option }
  | UnhandledResult of { func_name : string; loc : loc }
  | UnhandledOption of { func_name : string; loc : loc }
[@@deriving show, eq]

let exc_base_name = function
  | ExcName n -> n
  | ExcQualified (_, n) -> n
  | ExcOk -> "Ok"
  | ExcSome -> "Some"
  | ExcNothing -> "Nothing"
  | ExcUnion _ -> "Union"

let exc_matches a b =
  match a, b with
  | ExcOk, ExcOk -> true
  | ExcSome, ExcSome -> true
  | ExcNothing, ExcNothing -> true
  | ExcName n1, ExcName n2 -> n1 = n2
  | ExcQualified (m1, n1), ExcQualified (m2, n2) ->
    (m1 = m2 && n1 = n2) || n1 = n2
  | ExcName n, ExcQualified (_, qn) -> n = qn
  | ExcQualified (_, qn), ExcName n -> qn = n
  | _ -> false

let find_matching_exc exc_list target =
  List.find_opt (exc_matches target) exc_list

let check_raises_signature (signature : func_signature) (call : match_call) : error list =
  let required = ExcOk :: signature.declared_exceptions in
  let provided_list =
    if call.has_ok_handler then ExcOk :: call.handlers else call.handlers
  in
  let missing = List.filter (fun req -> find_matching_exc provided_list req = None) required in
  let extra = List.filter (fun prov -> find_matching_exc required prov = None) provided_list in
  let errors = [] in
  let errors =
    if not call.has_ok_handler then
      MissingOkHandler { func_name = call.func_name; loc = call.loc; call_loc = call.call_loc } :: errors
    else errors
  in
  let errors =
    let missing_list = List.filter (fun e -> not (exc_matches e ExcOk)) missing in
    if missing_list <> [] then
      MissingHandlers { func_name = call.func_name; missing = missing_list; loc = call.loc; call_loc = call.call_loc }
      :: errors
    else errors
  in
  let errors =
    if extra <> [] then
      ExtraHandlers { func_name = call.func_name; extra; loc = call.loc; call_loc = call.call_loc } :: errors
    else errors
  in
  errors

let check_option_signature (call : match_call) : error list =
  let errors = [] in
  let errors =
    if not call.has_some_handler then
      MissingSomeHandler { func_name = call.func_name; loc = call.loc; call_loc = call.call_loc } :: errors
    else errors
  in
  let errors =
    if not call.has_nothing_handler then
      MissingNothingHandler { func_name = call.func_name; loc = call.loc; call_loc = call.call_loc } :: errors
    else errors
  in
  (* Check for extra handlers - Option types only allow Some and Nothing *)
  let errors =
    if call.handlers <> [] then
      ExtraHandlers { func_name = call.func_name; extra = call.handlers; loc = call.loc; call_loc = call.call_loc } :: errors
    else errors
  in
  errors

let check_one (signatures : func_signature StringMap.t) (call : match_call) : error list =
  match StringMap.find_opt call.func_name signatures with
  | None -> [ UnknownFunction { name = call.func_name; loc = call.loc; call_loc = call.call_loc } ]
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
