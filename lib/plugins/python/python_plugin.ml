module P = Plugin
open Pyrethrum

let ( let* ) = Result.bind

let language = Ast.Python

let can_handle json =
  match json with
  | `Assoc fields ->
    let has_ast = List.mem_assoc "ast" fields in
    let lang = List.assoc_opt "language" fields in
    let is_python = match lang with
      | Some (`String "python") -> true
      | Some (`String "Python") -> true
      | None -> true
      | _ -> false
    in
    has_ast && is_python
  | _ -> false

let get_source_file json =
  match json with
  | `Assoc fields -> (
    match List.assoc_opt "source_file" fields with
    | Some (`String s) -> Some s
    | _ -> None)
  | _ -> None

let parse_raw_ast json =
  let source_file = get_source_file json |> Option.value ~default:"<unknown>" in
  let* ast_json =
    match json with
    | `Assoc fields -> (
      match List.assoc_opt "ast" fields with
      | Some v -> Ok v
      | None -> Error "Missing 'ast' field")
    | _ -> Error "Expected object"
  in
  let* module_ = Python_parse.parse_module ast_json in
  Ok (Python_extract.extract_from_module source_file module_)

let () =
  P.register_plugin (module struct
    let language = language
    let can_handle = can_handle
    let parse_raw_ast = parse_raw_ast
    let get_source_file = get_source_file
  end : P.LANGUAGE_PLUGIN)
