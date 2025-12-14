open Pyrethrum

(* Force linking of python plugin to register it *)
let () = ignore (Python_plugin.language)

let run_check input_source format_opt strict_opt =
  let format = match format_opt with Some f -> f | None -> Config.Text in
  let input =
    match input_source with
    | `Stdin -> In_channel.input_all In_channel.stdin
    | `File path -> In_channel.with_open_text path In_channel.input_all
  in
  let json =
    match Yojson.Safe.from_string input with
    | json -> json
    | exception Yojson.Json_error msg ->
      Fmt.epr "Error parsing JSON: %s@." msg;
      Stdlib.exit 2
  in
  match Plugin.parse_input json with
  | Error msg ->
      Fmt.epr "Error parsing input: %s@." msg;
      Stdlib.exit 2
  | Ok { language; signatures; matches; unhandled_calls } ->
      let errors = Exhaustiveness.check_all_with_unhandled signatures matches unhandled_calls in
      let diagnostics = List.map (Diagnostics.error_to_diagnostic ~language) errors in
      if diagnostics = [] then (
        if format = Config.Text then Fmt.pr "No exhaustiveness errors found.@.")
      else (
        let output =
          match format with
          | Config.Json -> Diagnostics.diagnostics_to_json diagnostics
          | Config.Text -> Diagnostics.diagnostics_to_string diagnostics
        in
        Fmt.pr "%s@." output;
        let has_errors =
          List.exists (fun d -> d.Diagnostics.severity = Diagnostics.Error) diagnostics
        in
        let exit_code =
          if has_errors then 1
          else if strict_opt then 1
          else 0
        in
        Stdlib.exit exit_code)

open Cmdliner

let format_conv =
  let parse s =
    match String.lowercase_ascii s with
    | "json" -> Ok Config.Json
    | "text" -> Ok Config.Text
    | _ -> Error (`Msg "format must be 'json' or 'text'")
  in
  let print fmt f =
    Format.fprintf fmt "%s" (match f with Config.Json -> "json" | Config.Text -> "text")
  in
  Arg.conv (parse, print)

let format_arg =
  let doc = "Output format: 'text' or 'json'" in
  Arg.(value & opt (some format_conv) None & info [ "format"; "f" ] ~docv:"FORMAT" ~doc)

let strict_arg =
  let doc = "Treat warnings as errors" in
  Arg.(value & flag & info [ "strict" ] ~doc)

let stdin_arg =
  let doc = "Read JSON input from stdin" in
  Arg.(value & flag & info [ "stdin" ] ~doc)

let file_arg =
  let doc = "Input JSON file" in
  Arg.(value & pos 0 (some file) None & info [] ~docv:"FILE" ~doc)

let check_cmd =
  let doc = "Check for exhaustiveness errors" in
  let man = [ `S Manpage.s_description; `P "Analyzes the input for exhaustiveness errors." ] in
  let info = Cmd.info "check" ~doc ~man in
  let term =
    Term.(
      const (fun stdin_flag file format strict ->
          let input_source =
            if stdin_flag then `Stdin
            else
              match file with
              | Some path -> `File path
              | None ->
                  Fmt.epr "Error: either --stdin or a file path is required@.";
                  Stdlib.exit 2
          in
          run_check input_source format strict)
      $ stdin_arg $ file_arg $ format_arg $ strict_arg)
  in
  Cmd.v info term

let main_cmd =
  let doc = "Static analyzer for exhaustive exception handling" in
  let man =
    [
      `S Manpage.s_description;
      `P "Pyrethrum analyzes code to ensure all declared exceptions are handled exhaustively.";
    ]
  in
  let info = Cmd.info "pyrethrum" ~version:"0.1.0" ~doc ~man in
  Cmd.group info [ check_cmd ]

let () = Stdlib.exit (Cmd.eval main_cmd)
