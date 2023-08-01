let () =
  let usage = Printf.sprintf
{|Eurydice: from Rust to C

Usage: %s [OPTIONS] FILES

FILES are .llbc files produced by Charon. Eurydice will generate one C file per
llbc file.

Supported options:|}
    Sys.argv.(0)
  in
  let module O = Eurydice.Options in
  let spec = [
    "--log", Arg.Set_string O.log_level, " log level, use * for everything";
  ] in
  let spec = Arg.align spec in
  let files = ref [] in
  let fatal_error = Printf.kprintf (fun s -> print_endline s; exit 255) in
  let anon_fun f =
    if Filename.check_suffix f ".llbc" then
      files := f :: !files
    else
      fatal_error "Unknown file extension for %s" f
  in
  begin try
    Arg.parse spec anon_fun usage
  with e ->
    Printf.printf "Error parsing command-line: %s\n%s\n" (Printexc.get_backtrace ()) (Printexc.to_string e);
    fatal_error "Incorrect invocation, was: %s\n"
      (String.concat "␣" (Array.to_list Sys.argv))
  end;

  if !files = [] then
    fatal_error "%s" (Arg.usage_string spec usage);

  (* This is where the action happens *)
  Eurydice.Logging.enable_logging !O.log_level;

  let files = Eurydice.Builtin.files @ List.map (fun filename ->
    let llbc = Eurydice.LoadLlbc.load_file filename in
    Eurydice.AstOfLlbc.file_of_crate llbc
  ) !files in

  Printf.printf "✅ LLBC ➡️  AST\n";
  let terminal_width = Terminal.Size.(match get_dimensions () with Some d -> d.columns | None -> 80) in
  let print files =
    PPrint.(ToChannel.pretty 0.95 terminal_width stdout (Krml.PrintAst.print_files files ^^ hardline))
  in

  let files = Eurydice.PreCleanup.expand_array_copies files in
  let files = Eurydice.PreCleanup.flatten_sequences files in

  let errors, files = Krml.Checker.check_everything ~warn:true files in
  if errors then
    exit 1;

  Printf.printf "✅ Initial check\n";

  let files = Eurydice.Cleanup1.cleanup files in
  print files;

  let errors, files = Krml.Checker.check_everything ~warn:true files in
  if errors then
    exit 1;

  Printf.printf "✅ Done\n";

  print files
