open Pyrethrum
open Alcotest

let loc_testable = testable Ast.pp_loc Ast.equal_loc
let exc_type_testable = testable Ast.pp_exc_type Ast.equal_exc_type
let error_testable = testable Exhaustiveness.pp_error Exhaustiveness.equal_error

let test_loc = { Ast.file = "test.py"; line = 10; col = 5; end_line = 10; end_col = 20 }

let test_parse_loc () =
  let json =
    `Assoc
      [
        ("file", `String "test.py");
        ("line", `Int 10);
        ("col", `Int 5);
        ("end_line", `Int 10);
        ("end_col", `Int 20);
      ]
  in
  match Parse.parse_loc json with
  | Ok loc -> check loc_testable "parsed loc" test_loc loc
  | Error msg -> fail msg

let test_parse_exc_type_name () =
  let json = `Assoc [ ("kind", `String "name"); ("name", `String "ValueError") ] in
  match Parse.parse_exc_type json with
  | Ok exc -> check exc_type_testable "parsed exc_type" (Ast.ExcName "ValueError") exc
  | Error msg -> fail msg

let test_parse_exc_type_qualified () =
  let json =
    `Assoc
      [ ("kind", `String "qualified"); ("module", `String "mylib"); ("name", `String "MyError") ]
  in
  match Parse.parse_exc_type json with
  | Ok exc ->
      check exc_type_testable "parsed qualified" (Ast.ExcQualified ("mylib", "MyError")) exc
  | Error msg -> fail msg

let test_parse_exc_type_ok () =
  let json = `Assoc [ ("kind", `String "ok") ] in
  match Parse.parse_exc_type json with
  | Ok exc -> check exc_type_testable "parsed ok" Ast.ExcOk exc
  | Error msg -> fail msg

let test_exhaustiveness_missing_handler () =
  let signature =
    {
      Ast.name = "get_user";
      qualified_name = None;
      declared_exceptions = [ Ast.ExcName "NotFound"; Ast.ExcName "InvalidId" ];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigRaises;
    }
  in
  let call =
    {
      Ast.func_name = "get_user";
      handlers = [ Ast.ExcName "NotFound" ];
      has_ok_handler = true;
      has_some_handler = false;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchFunctionCall;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [
      Exhaustiveness.MissingHandlers
        { func_name = "get_user"; missing = [ Ast.ExcName "InvalidId" ]; loc = test_loc; call_loc = None };
    ]
    errors

let test_exhaustiveness_extra_handler () =
  let signature =
    {
      Ast.name = "get_user";
      qualified_name = None;
      declared_exceptions = [ Ast.ExcName "NotFound" ];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigRaises;
    }
  in
  let call =
    {
      Ast.func_name = "get_user";
      handlers = [ Ast.ExcName "NotFound"; Ast.ExcName "Unexpected" ];
      has_ok_handler = true;
      has_some_handler = false;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchFunctionCall;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [
      Exhaustiveness.ExtraHandlers
        { func_name = "get_user"; extra = [ Ast.ExcName "Unexpected" ]; loc = test_loc; call_loc = None };
    ]
    errors

let test_exhaustiveness_missing_ok () =
  let signature =
    {
      Ast.name = "get_user";
      qualified_name = None;
      declared_exceptions = [ Ast.ExcName "NotFound" ];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigRaises;
    }
  in
  let call =
    {
      Ast.func_name = "get_user";
      handlers = [ Ast.ExcName "NotFound" ];
      has_ok_handler = false;
      has_some_handler = false;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchFunctionCall;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [ Exhaustiveness.MissingOkHandler { func_name = "get_user"; loc = test_loc; call_loc = None } ]
    errors

let test_exhaustiveness_all_handled () =
  let signature =
    {
      Ast.name = "get_user";
      qualified_name = None;
      declared_exceptions = [ Ast.ExcName "NotFound"; Ast.ExcName "InvalidId" ];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigRaises;
    }
  in
  let call =
    {
      Ast.func_name = "get_user";
      handlers = [ Ast.ExcName "NotFound"; Ast.ExcName "InvalidId" ];
      has_ok_handler = true;
      has_some_handler = false;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchFunctionCall;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "no errors" [] errors

let test_exhaustiveness_unknown_function () =
  let call =
    {
      Ast.func_name = "unknown_func";
      handlers = [ Ast.ExcName "SomeError" ];
      has_ok_handler = true;
      has_some_handler = false;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchFunctionCall;
    }
  in
  let errors = Exhaustiveness.check_all [] [ call ] in
  check (list error_testable) "one error"
    [ Exhaustiveness.UnknownFunction { name = "unknown_func"; loc = test_loc; call_loc = None } ]
    errors

let test_exhaustiveness_option_all_handled () =
  let signature =
    {
      Ast.name = "find_user";
      qualified_name = None;
      declared_exceptions = [];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigOption;
    }
  in
  let call =
    {
      Ast.func_name = "find_user";
      handlers = [];
      has_ok_handler = false;
      has_some_handler = true;
      has_nothing_handler = true;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchStatement;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "no errors" [] errors

let test_exhaustiveness_option_missing_some () =
  let signature =
    {
      Ast.name = "find_user";
      qualified_name = None;
      declared_exceptions = [];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigOption;
    }
  in
  let call =
    {
      Ast.func_name = "find_user";
      handlers = [];
      has_ok_handler = false;
      has_some_handler = false;
      has_nothing_handler = true;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchStatement;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [ Exhaustiveness.MissingSomeHandler { func_name = "find_user"; loc = test_loc; call_loc = None } ]
    errors

let test_exhaustiveness_option_missing_nothing () =
  let signature =
    {
      Ast.name = "find_user";
      qualified_name = None;
      declared_exceptions = [];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigOption;
    }
  in
  let call =
    {
      Ast.func_name = "find_user";
      handlers = [];
      has_ok_handler = false;
      has_some_handler = true;
      has_nothing_handler = false;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchStatement;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [ Exhaustiveness.MissingNothingHandler { func_name = "find_user"; loc = test_loc; call_loc = None } ]
    errors

let test_exhaustiveness_option_extra_handler () =
  let signature =
    {
      Ast.name = "find_user";
      qualified_name = None;
      declared_exceptions = [];
      loc = test_loc;
      is_async = false;
      signature_type = Ast.SigOption;
    }
  in
  let call =
    {
      Ast.func_name = "find_user";
      handlers = [ Ast.ExcName "SomeError" ];  (* Extra handler not allowed for Option *)
      has_ok_handler = false;
      has_some_handler = true;
      has_nothing_handler = true;
      loc = test_loc;
      call_loc = None;
      kind = Ast.MatchStatement;
    }
  in
  let errors = Exhaustiveness.check_all [ signature ] [ call ] in
  check (list error_testable) "one error"
    [
      Exhaustiveness.ExtraHandlers
        { func_name = "find_user"; extra = [ Ast.ExcName "SomeError" ]; loc = test_loc; call_loc = None };
    ]
    errors

let test_diagnostic_json () =
  let diag =
    {
      Diagnostics.file = "test.py";
      line = 10;
      column = 5;
      end_line = 10;
      end_column = 20;
      call_line = None;
      severity = Diagnostics.Error;
      code = Diagnostics.EXH001;
      message = "Test message";
      suggestions = [];
    }
  in
  let json_str = Diagnostics.diagnostics_to_json [ diag ] in
  let string_contains haystack needle =
    let n = String.length needle in
    let h = String.length haystack in
    if n > h then false
    else
      let rec check i =
        if i > h - n then false
        else if String.sub haystack i n = needle then true
        else check (i + 1)
      in
      check 0
  in
  check bool "contains file" true (string_contains json_str "test.py");
  check bool "contains message" true (string_contains json_str "Test message")

let test_config_default () =
  let cfg = Config.default in
  check bool "not strict" false cfg.strict_mode;
  check (list string) "no ignores" [] cfg.ignore_patterns;
  check bool "text format" true (cfg.format = Config.Text)

let test_config_load () =
  let json = {|{"strict": true, "format": "json", "ignore": ["test_*.py"]}|} in
  match Config.load_from_string json with
  | Ok cfg ->
      check bool "strict" true cfg.strict_mode;
      check (list string) "ignores" [ "test_*.py" ] cfg.ignore_patterns;
      check bool "json format" true (cfg.format = Config.Json)
  | Error msg -> fail msg

let () =
  run "Pyrethrum"
    [
      ( "parse",
        [
          test_case "parse_loc" `Quick test_parse_loc;
          test_case "parse_exc_type_name" `Quick test_parse_exc_type_name;
          test_case "parse_exc_type_qualified" `Quick test_parse_exc_type_qualified;
          test_case "parse_exc_type_ok" `Quick test_parse_exc_type_ok;
        ] );
      ( "exhaustiveness",
        [
          test_case "missing_handler" `Quick test_exhaustiveness_missing_handler;
          test_case "extra_handler" `Quick test_exhaustiveness_extra_handler;
          test_case "missing_ok" `Quick test_exhaustiveness_missing_ok;
          test_case "all_handled" `Quick test_exhaustiveness_all_handled;
          test_case "unknown_function" `Quick test_exhaustiveness_unknown_function;
          test_case "option_all_handled" `Quick test_exhaustiveness_option_all_handled;
          test_case "option_missing_some" `Quick test_exhaustiveness_option_missing_some;
          test_case "option_missing_nothing" `Quick test_exhaustiveness_option_missing_nothing;
          test_case "option_extra_handler" `Quick test_exhaustiveness_option_extra_handler;
        ] );
      ( "diagnostics",
        [ test_case "json_output" `Quick test_diagnostic_json ] );
      ( "config",
        [
          test_case "default" `Quick test_config_default;
          test_case "load" `Quick test_config_load;
        ] );
    ]
