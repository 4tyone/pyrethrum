open Ast

type error_code =
  | EXH001
  | EXH002
  | EXH003
  | EXH004
  | EXH005
  | EXH006
  | EXH007
  | EXH008
[@@deriving show, eq]

let error_code_to_string = function
  | EXH001 -> "EXH001"
  | EXH002 -> "EXH002"
  | EXH003 -> "EXH003"
  | EXH004 -> "EXH004"
  | EXH005 -> "EXH005"
  | EXH006 -> "EXH006"
  | EXH007 -> "EXH007"
  | EXH008 -> "EXH008"

type severity =
  | Error
  | Warning
[@@deriving show, eq]

type suggestion = { action : string; exception_name : string option }
[@@deriving show, eq]

type diagnostic = {
  file : string;
  line : int;
  column : int;
  end_line : int;
  end_column : int;
  severity : severity;
  code : error_code;
  message : string;
  suggestions : suggestion list;
}
[@@deriving show, eq]

let rec exc_type_to_string = function
  | ExcName name -> name
  | ExcQualified (module_, name) -> module_ ^ "." ^ name
  | ExcUnion types -> String.concat " | " (List.map exc_type_to_string types)
  | ExcOk -> "Ok"
  | ExcSome -> "Some"
  | ExcNothing -> "Nothing"

let error_to_diagnostic ?(language=Unknown) (error : Exhaustiveness.error) : diagnostic =
  let decorator = language_decorator_name language in
  let match_fn = language_match_name language in
  match error with
  | MissingHandlers { func_name; missing; loc } ->
      let missing_names = List.map exc_type_to_string missing in
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH001;
        message =
          Printf.sprintf "Non-exhaustive %s on `%s`: missing %s" match_fn func_name
            (String.concat ", " missing_names);
        suggestions =
          List.map (fun name -> { action = "add_handler"; exception_name = Some name }) missing_names;
      }
  | ExtraHandlers { func_name; extra; loc } ->
      let extra_names = List.map exc_type_to_string extra in
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Warning;
        code = EXH002;
        message =
          Printf.sprintf "%s on `%s` has handlers for undeclared exceptions: %s"
            (String.capitalize_ascii match_fn) func_name (String.concat ", " extra_names);
        suggestions =
          List.map
            (fun name -> { action = "remove_handler"; exception_name = Some name })
            extra_names;
      }
  | MissingOkHandler { func_name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH003;
        message = Printf.sprintf "%s on `%s` is missing handler for Ok case"
            (String.capitalize_ascii match_fn) func_name;
        suggestions = [ { action = "add_handler"; exception_name = Some "Ok" } ];
      }
  | MissingSomeHandler { func_name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH005;
        message = Printf.sprintf "%s on `%s` is missing handler for Some case"
            (String.capitalize_ascii match_fn) func_name;
        suggestions = [ { action = "add_handler"; exception_name = Some "Some" } ];
      }
  | MissingNothingHandler { func_name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH006;
        message = Printf.sprintf "%s on `%s` is missing handler for Nothing case"
            (String.capitalize_ascii match_fn) func_name;
        suggestions = [ { action = "add_handler"; exception_name = Some "Nothing" } ];
      }
  | UnknownFunction { name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Warning;
        code = EXH004;
        message = Printf.sprintf "%s called on `%s` which has no %s signature" match_fn name decorator;
        suggestions = [];
      }
  | UnhandledResult { func_name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH007;
        message = Printf.sprintf "Result from `%s` must be handled with %s or match-case" func_name match_fn;
        suggestions = [ { action = "add_match"; exception_name = None } ];
      }
  | UnhandledOption { func_name; loc } ->
      {
        file = loc.file;
        line = loc.line;
        column = loc.col;
        end_line = loc.end_line;
        end_column = loc.end_col;
        severity = Error;
        code = EXH008;
        message = Printf.sprintf "Option from `%s` must be handled with %s or match-case" func_name match_fn;
        suggestions = [ { action = "add_match"; exception_name = None } ];
      }

let suggestion_to_json (s : suggestion) : Yojson.Safe.t =
  `Assoc
    ([ ("action", `String s.action) ]
    @ (match s.exception_name with Some n -> [ ("exception", `String n) ] | None -> []))

let diagnostic_to_json (d : diagnostic) : Yojson.Safe.t =
  `Assoc
    [
      ("file", `String d.file);
      ("line", `Int d.line);
      ("column", `Int d.column);
      ("endLine", `Int d.end_line);
      ("endColumn", `Int d.end_column);
      ("severity", `String (if d.severity = Error then "error" else "warning"));
      ("code", `String (error_code_to_string d.code));
      ("message", `String d.message);
      ("suggestions", `List (List.map suggestion_to_json d.suggestions));
    ]

let diagnostics_to_json (ds : diagnostic list) : string =
  let json = `Assoc [ ("diagnostics", `List (List.map diagnostic_to_json ds)) ] in
  Yojson.Safe.pretty_to_string json

let diagnostic_to_string (d : diagnostic) : string =
  let severity_str = if d.severity = Error then "error" else "warning" in
  Printf.sprintf "%s:%d:%d: %s [%s]: %s" d.file d.line d.column severity_str
    (error_code_to_string d.code) d.message

let diagnostics_to_string (ds : diagnostic list) : string =
  String.concat "\n" (List.map diagnostic_to_string ds)
