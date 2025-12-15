open Ast

let ( let* ) = Result.bind
let ( >>= ) = Result.bind

let member key json =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some v -> Ok v
      | None -> Error (Printf.sprintf "missing key: %s" key))
  | _ -> Error "expected object"

let to_string json =
  match json with
  | `String s -> Ok s
  | _ -> Error "expected string"

let to_int json =
  match json with
  | `Int i -> Ok i
  | _ -> Error "expected int"

let to_bool json =
  match json with
  | `Bool b -> Ok b
  | _ -> Error "expected bool"

let to_list json =
  match json with
  | `List l -> Ok l
  | _ -> Error "expected list"

let to_string_opt json =
  match json with
  | `String s -> Ok (Some s)
  | `Null -> Ok None
  | _ -> Error "expected string or null"

let parse_loc json =
  let* file = member "file" json >>= to_string in
  let* line = member "line" json >>= to_int in
  let* col = member "col" json >>= to_int in
  let* end_line = member "end_line" json >>= to_int in
  let* end_col = member "end_col" json >>= to_int in
  Ok { file; line; col; end_line; end_col }

let list_map f lst =
  let rec aux acc = function
    | [] -> Ok (List.rev acc)
    | x :: xs ->
        let* y = f x in
        aux (y :: acc) xs
  in
  aux [] lst

let rec parse_exc_type json =
  let* kind = member "kind" json >>= to_string in
  match kind with
  | "name" ->
      let* name = member "name" json >>= to_string in
      Ok (ExcName name)
  | "qualified" ->
      let* module_ = member "module" json >>= to_string in
      let* name = member "name" json >>= to_string in
      Ok (ExcQualified (module_, name))
  | "union" ->
      let* types = member "types" json >>= to_list in
      let* parsed = list_map parse_exc_type types in
      Ok (ExcUnion parsed)
  | "ok" -> Ok ExcOk
  | "some" -> Ok ExcSome
  | "nothing" -> Ok ExcNothing
  | other -> Error (Printf.sprintf "unknown exc_type kind: %s" other)

let parse_signature_type json =
  let* s = to_string json in
  match s with
  | "raises" -> Ok SigRaises
  | "option" -> Ok SigOption
  | other -> Error (Printf.sprintf "unknown signature_type: %s" other)

let to_bool_default default json =
  match json with
  | `Bool b -> Ok b
  | `Null -> Ok default
  | _ -> Error "expected bool"

let member_opt key json =
  match json with
  | `Assoc pairs -> Ok (List.assoc_opt key pairs)
  | _ -> Error "expected object"

let parse_func_signature json =
  let* name = member "name" json >>= to_string in
  let* qualified_name = member "qualified_name" json >>= to_string_opt in
  let* exceptions = member "declared_exceptions" json >>= to_list in
  let* declared_exceptions = list_map parse_exc_type exceptions in
  let* loc = member "loc" json >>= parse_loc in
  let* is_async = member "is_async" json >>= to_bool in
  let* sig_type_opt = member_opt "signature_type" json in
  let* signature_type = match sig_type_opt with
    | Some st -> parse_signature_type st
    | None -> Ok SigRaises  (* default for backwards compatibility *)
  in
  Ok { name; qualified_name; declared_exceptions; loc; is_async; signature_type }

let parse_match_kind json =
  let* s = to_string json in
  match s with
  | "function_call" -> Ok MatchFunctionCall
  | "statement" -> Ok MatchStatement
  | other -> Error (Printf.sprintf "unknown match_kind: %s" other)

let parse_match_call json =
  let* func_name = member "func_name" json >>= to_string in
  let* handlers_json = member "handlers" json >>= to_list in
  let* handlers = list_map parse_exc_type handlers_json in
  let* has_ok_handler = member "has_ok_handler" json >>= to_bool in
  let* has_some_opt = member_opt "has_some_handler" json in
  let* has_some_handler = match has_some_opt with
    | Some v -> to_bool v
    | None -> Ok false
  in
  let* has_nothing_opt = member_opt "has_nothing_handler" json in
  let* has_nothing_handler = match has_nothing_opt with
    | Some v -> to_bool v
    | None -> Ok false
  in
  let* loc = member "loc" json >>= parse_loc in
  let* call_loc_opt = member_opt "call_loc" json in
  let* call_loc = match call_loc_opt with
    | Some (`Null) -> Ok None
    | Some v -> let* l = parse_loc v in Ok (Some l)
    | None -> Ok None
  in
  let* kind = member "kind" json >>= parse_match_kind in
  Ok { func_name; handlers; has_ok_handler; has_some_handler; has_nothing_handler; loc; call_loc; kind }

let parse_language json =
  match json with
  | `String s -> (
      match String.lowercase_ascii s with
      | "python" -> Ok Python
      | "typescript" -> Ok TypeScript
      | "javascript" -> Ok JavaScript
      | "go" -> Ok Go
      | "java" -> Ok Java
      | "php" -> Ok PHP
      | _ -> Ok Unknown)
  | `Null -> Ok Unknown
  | _ -> Error "expected string for language"

let parse_file json =
  let* signatures_json = member "signatures" json >>= to_list in
  let* signatures = list_map parse_func_signature signatures_json in
  let* matches_json = member "matches" json >>= to_list in
  let* matches = list_map parse_match_call matches_json in
  Ok (signatures, matches)

let parse_unhandled_call json =
  let* func_name = member "func_name" json >>= to_string in
  let* loc = member "loc" json >>= parse_loc in
  let* sig_type_str = member "signature_type" json >>= to_string in
  let* signature_type = match sig_type_str with
    | "raises" -> Ok SigRaises
    | "option" -> Ok SigOption
    | other -> Error (Printf.sprintf "unknown signature_type: %s" other)
  in
  Ok { func_name; loc; signature_type }

let parse_analysis_input json =
  let* lang_opt = member_opt "language" json in
  let* language = match lang_opt with
    | Some l -> parse_language l
    | None -> Ok Unknown
  in
  let* signatures_json = member "signatures" json >>= to_list in
  let* signatures = list_map parse_func_signature signatures_json in
  let* matches_json = member "matches" json >>= to_list in
  let* matches = list_map parse_match_call matches_json in
  let* unhandled_opt = member_opt "unhandled_calls" json in
  let* unhandled_calls = match unhandled_opt with
    | Some uc_json ->
        let* uc_list = to_list uc_json in
        list_map parse_unhandled_call uc_list
    | None -> Ok []
  in
  Ok { language; signatures; matches; unhandled_calls }

let parse_file_from_string s =
  match Yojson.Safe.from_string s with
  | json -> parse_file json
  | exception Yojson.Json_error msg -> Error (Printf.sprintf "JSON parse error: %s" msg)

let parse_analysis_input_from_string s =
  match Yojson.Safe.from_string s with
  | json -> parse_analysis_input json
  | exception Yojson.Json_error msg -> Error (Printf.sprintf "JSON parse error: %s" msg)
