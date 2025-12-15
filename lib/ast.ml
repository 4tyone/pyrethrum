type language =
  | Python
  | TypeScript
  | JavaScript
  | Go
  | Java
  | PHP
  | Unknown
[@@deriving show, eq, ord]

type loc = {
  file : string;
  line : int;
  col : int;
  end_line : int;
  end_col : int;
}
[@@deriving show, eq, ord]

let dummy_loc = { file = "<unknown>"; line = 0; col = 0; end_line = 0; end_col = 0 }

type exc_type =
  | ExcName of string
  | ExcQualified of string * string
  | ExcUnion of exc_type list
  | ExcOk
  | ExcSome
  | ExcNothing
[@@deriving show, eq, ord]

type signature_type =
  | SigRaises
  | SigOption
[@@deriving show, eq]

type func_signature = {
  name : string;
  qualified_name : string option;
  declared_exceptions : exc_type list;
  loc : loc;
  is_async : bool;
  signature_type : signature_type;
}
[@@deriving show, eq]

type match_kind =
  | MatchFunctionCall
  | MatchStatement
[@@deriving show, eq]

type match_call = {
  func_name : string;
  handlers : exc_type list;
  has_ok_handler : bool;
  has_some_handler : bool;
  has_nothing_handler : bool;
  loc : loc;
  call_loc : loc option;
  kind : match_kind;
}
[@@deriving show, eq]

type unhandled_call = {
  func_name : string;
  loc : loc;
  signature_type : signature_type;
}
[@@deriving show, eq]

type analysis_input = {
  language : language;
  signatures : func_signature list;
  matches : match_call list;
  unhandled_calls : unhandled_call list;
}
[@@deriving show, eq]

module ExcSet = Set.Make (struct
  type t = exc_type

  let compare = compare_exc_type
end)

module StringMap = Map.Make (String)

let language_decorator_name = function
  | Python -> "@raises"
  | TypeScript -> "raises()"
  | JavaScript -> "raises()"
  | Go -> "raises()"
  | Java -> "@Raises"
  | PHP -> "#[Raises]"
  | Unknown -> "@raises"

let language_match_name = function
  | Python -> "match"
  | TypeScript -> "match()"
  | JavaScript -> "match()"
  | Go -> "Match()"
  | Java -> "Match.on()"
  | PHP -> "match_result()"
  | Unknown -> "match"
