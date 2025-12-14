open Pyrethrum

type 'a parse_result = ('a, string) result

module type LANGUAGE_PLUGIN = sig
  val language : Ast.language
  val can_handle : Yojson.Safe.t -> bool
  val parse_raw_ast : Yojson.Safe.t -> Ast.analysis_input parse_result
  val get_source_file : Yojson.Safe.t -> string option
end

let plugins : (module LANGUAGE_PLUGIN) list ref = ref []

let register_plugin (plugin : (module LANGUAGE_PLUGIN)) =
  plugins := plugin :: !plugins

let find_plugin (json : Yojson.Safe.t) : (module LANGUAGE_PLUGIN) option =
  List.find_opt (fun (module P : LANGUAGE_PLUGIN) -> P.can_handle json) !plugins

let is_raw_format (json : Yojson.Safe.t) : bool =
  match json with
  | `Assoc fields ->
    List.mem_assoc "ast" fields && not (List.mem_assoc "signatures" fields)
  | _ -> false

let parse_input (json : Yojson.Safe.t) : Ast.analysis_input parse_result =
  if is_raw_format json then
    match find_plugin json with
    | Some (module P : LANGUAGE_PLUGIN) -> P.parse_raw_ast json
    | None -> Error "No plugin found for raw AST format"
  else
    Parse.parse_analysis_input json
