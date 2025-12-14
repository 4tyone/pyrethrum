type output_format =
  | Text
  | Json
[@@deriving show, eq]

type t = {
  strict_mode : bool;
  ignore_patterns : string list;
  format : output_format;
}
[@@deriving show, eq]

let default = { strict_mode = false; ignore_patterns = []; format = Text }

let ( let* ) = Result.bind

let member key json =
  match json with
  | `Assoc pairs -> List.assoc_opt key pairs
  | _ -> None

let load_from_string s =
  match Yojson.Safe.from_string s with
  | `Assoc _ as json ->
      let strict_mode =
        match member "strict" json with
        | Some (`Bool b) -> b
        | _ -> default.strict_mode
      in
      let ignore_patterns =
        match member "ignore" json with
        | Some (`List items) ->
            List.filter_map
              (function
                | `String s -> Some s
                | _ -> None)
              items
        | _ -> default.ignore_patterns
      in
      let format =
        match member "format" json with
        | Some (`String "json") -> Json
        | Some (`String "text") -> Text
        | _ -> default.format
      in
      Ok { strict_mode; ignore_patterns; format }
  | _ -> Error "config must be a JSON object"
  | exception Yojson.Json_error msg -> Error (Printf.sprintf "JSON parse error: %s" msg)

let load_from_file path =
  try
    let content = In_channel.with_open_text path In_channel.input_all in
    load_from_string content
  with
  | Sys_error msg -> Error msg
