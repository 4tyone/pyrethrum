type loc = {
  lineno : int;
  col_offset : int;
  end_lineno : int;
  end_col_offset : int;
}

type identifier = string

type expr =
  | Name of { id : identifier; loc : loc }
  | Attribute of { value : expr; attr : identifier; loc : loc }
  | Call of { func : expr; args : expr list; keywords : keyword list; loc : loc }
  | Constant of { value : constant_value; loc : loc }
  | Subscript of { value : expr; slice : expr; loc : loc }
  | BinOp of { left : expr; right : expr; loc : loc }
  | Tuple of { elts : expr list; loc : loc }
  | List of { elts : expr list; loc : loc }
  | Dict of { keys : expr option list; values : expr list; loc : loc }
  | IfExp of { test : expr; body : expr; orelse : expr; loc : loc }
  | Lambda of { body : expr; loc : loc }
  | UnaryOp of { operand : expr; loc : loc }
  | Compare of { left : expr; comparators : expr list; loc : loc }
  | BoolOp of { values : expr list; loc : loc }
  | Starred of { value : expr; loc : loc }
  | Await of { value : expr; loc : loc }
  | Yield of { value : expr option; loc : loc }
  | YieldFrom of { value : expr; loc : loc }
  | JoinedStr of { values : expr list; loc : loc }
  | FormattedValue of { value : expr; loc : loc }
  | NamedExpr of { target : expr; value : expr; loc : loc }
  | Slice of { lower : expr option; upper : expr option; step : expr option; loc : loc }
  | UnknownExpr of { loc : loc }

and keyword = { arg : identifier option; value : expr }

and constant_value =
  | ConstString of string
  | ConstInt of int
  | ConstFloat of float
  | ConstBool of bool
  | ConstNone
  | ConstBytes of string
  | ConstEllipsis
  | ConstOther

type pattern =
  | MatchValue of { value : expr; loc : loc }
  | MatchSingleton of { value : constant_value; loc : loc }
  | MatchSequence of { patterns : pattern list; loc : loc }
  | MatchMapping of { keys : expr list; patterns : pattern list; loc : loc }
  | MatchClass of { cls : expr; patterns : pattern list; kwd_patterns : pattern list; loc : loc }
  | MatchStar of { name : identifier option; loc : loc }
  | MatchAs of { pattern : pattern option; name : identifier option; loc : loc }
  | MatchOr of { patterns : pattern list; loc : loc }
  | UnknownPattern of { loc : loc }

type match_case = {
  pattern : pattern;
  guard : expr option;
  case_body : stmt list;
}

and stmt =
  | FunctionDef of {
      name : identifier;
      args : arguments;
      body : stmt list;
      decorator_list : expr list;
      returns : expr option;
      is_async : bool;
      loc : loc;
    }
  | ClassDef of {
      name : identifier;
      bases : expr list;
      body : stmt list;
      decorator_list : expr list;
      loc : loc;
    }
  | Return of { value : expr option; loc : loc }
  | Assign of { targets : expr list; value : expr; loc : loc }
  | AnnAssign of { target : expr; annotation : expr; value : expr option; loc : loc }
  | AugAssign of { target : expr; value : expr; loc : loc }
  | For of { target : expr; iter : expr; body : stmt list; orelse : stmt list; loc : loc }
  | AsyncFor of { target : expr; iter : expr; body : stmt list; orelse : stmt list; loc : loc }
  | While of { test : expr; body : stmt list; orelse : stmt list; loc : loc }
  | If of { test : expr; body : stmt list; orelse : stmt list; loc : loc }
  | With of { items : withitem list; body : stmt list; loc : loc }
  | AsyncWith of { items : withitem list; body : stmt list; loc : loc }
  | Match of { subject : expr; cases : match_case list; loc : loc }
  | Raise of { exc : expr option; cause : expr option; loc : loc }
  | Try of { body : stmt list; handlers : excepthandler list; orelse : stmt list; finalbody : stmt list; loc : loc }
  | TryStar of { body : stmt list; handlers : excepthandler list; orelse : stmt list; finalbody : stmt list; loc : loc }
  | Assert of { test : expr; msg : expr option; loc : loc }
  | Import of { names : alias list; loc : loc }
  | ImportFrom of { module_ : identifier option; names : alias list; level : int; loc : loc }
  | Global of { names : identifier list; loc : loc }
  | Nonlocal of { names : identifier list; loc : loc }
  | Expr of { value : expr; loc : loc }
  | Pass of { loc : loc }
  | Break of { loc : loc }
  | Continue of { loc : loc }
  | Delete of { targets : expr list; loc : loc }
  | UnknownStmt of { loc : loc }

and arguments = {
  posonlyargs : arg list;
  args : arg list;
  vararg : arg option;
  kwonlyargs : arg list;
  kw_defaults : expr option list;
  kwarg : arg option;
  defaults : expr list;
}

and arg = {
  arg_name : identifier;
  annotation : expr option;
  arg_loc : loc;
}

and withitem = {
  context_expr : expr;
  optional_vars : expr option;
}

and excepthandler = {
  type_ : expr option;
  name : identifier option;
  handler_body : stmt list;
  handler_loc : loc;
}

and alias = {
  alias_name : identifier;
  alias_asname : identifier option;
}

type module_ = {
  body : stmt list;
  type_ignores : unit list;
}

let dummy_loc = { lineno = 0; col_offset = 0; end_lineno = 0; end_col_offset = 0 }

let get_expr_loc = function
  | Name { loc; _ } | Attribute { loc; _ } | Call { loc; _ }
  | Constant { loc; _ } | Subscript { loc; _ } | BinOp { loc; _ }
  | Tuple { loc; _ } | List { loc; _ } | Dict { loc; _ }
  | IfExp { loc; _ } | Lambda { loc; _ } | UnaryOp { loc; _ }
  | Compare { loc; _ } | BoolOp { loc; _ } | Starred { loc; _ }
  | Await { loc; _ } | Yield { loc; _ } | YieldFrom { loc; _ }
  | JoinedStr { loc; _ } | FormattedValue { loc; _ }
  | NamedExpr { loc; _ } | Slice { loc; _ } | UnknownExpr { loc } -> loc

let get_stmt_loc = function
  | FunctionDef { loc; _ } | ClassDef { loc; _ } | Return { loc; _ }
  | Assign { loc; _ } | AnnAssign { loc; _ } | AugAssign { loc; _ }
  | For { loc; _ } | AsyncFor { loc; _ } | While { loc; _ }
  | If { loc; _ } | With { loc; _ } | AsyncWith { loc; _ }
  | Match { loc; _ } | Raise { loc; _ } | Try { loc; _ } | TryStar { loc; _ }
  | Assert { loc; _ } | Import { loc; _ } | ImportFrom { loc; _ }
  | Global { loc; _ } | Nonlocal { loc; _ } | Expr { loc; _ }
  | Pass { loc } | Break { loc } | Continue { loc }
  | Delete { loc; _ } | UnknownStmt { loc } -> loc
