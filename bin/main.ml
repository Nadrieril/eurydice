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
  let debug s = Krml.Options.debug_modules := Krml.KString.split_on_char ',' s @ !Krml.Options.debug_modules in
  let spec = [
    "--log", Arg.Set_string O.log_level, " log level, use * for everything";
    "--debug", Arg.String debug, " debug options, to be passed to krml";
    "--output", Arg.Set_string Krml.Options.tmpdir, " output directory in which to write files";
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

  let terminal_width = Terminal.Size.(match get_dimensions () with Some d -> d.columns | None -> 80) in
  let pfiles b files =
    PPrint.(ToBuffer.pretty 0.95 terminal_width b (Krml.PrintAst.print_files files ^^ hardline))
  in

  (* This is where the action happens *)
  Eurydice.Logging.enable_logging !O.log_level;
  (* Type applications are compiled as a regular external type. *)
  Krml.Options.(
    allow_tapps := true;
    minimal := true;
    add_include := [ All, "\"eurydice_glue.h\"" ];
    (* header := "/* This file compiled from Rust to C by Eurydice \ *)
    (*   <http://github.com/aeneasverif/eurydice> */"; *)
    parentheses := true;
  );

  let files = Eurydice.Builtin.files @ List.map (fun filename ->
    let llbc = Eurydice.LoadLlbc.load_file filename in
    Eurydice.AstOfLlbc.file_of_crate llbc
  ) !files in

  Printf.printf "1️⃣ LLBC ➡️  AST\n";
  let files = Eurydice.PreCleanup.expand_array_copies files in
  let files = Eurydice.PreCleanup.flatten_sequences files in

  Eurydice.Logging.log "Phase1" "%a" pfiles files;
  let errors, files = Krml.Checker.check_everything ~warn:true files in
  if errors then
    exit 1;

  Printf.printf "2️⃣ Cleanup\n";
  let files = Eurydice.Cleanup1.cleanup files in

  Eurydice.Logging.log "Phase2" "%a" pfiles files;
  let errors, files = Krml.Checker.check_everything ~warn:true files in
  if errors then
    exit 1;

  Printf.printf "3️⃣ Monomorphization, datatypes\n";
  let files = Krml.Monomorphization.functions files in
  let files = Krml.Monomorphization.datatypes files in
  let files = Krml.DataTypes.simplify files in
  let files = Krml.DataTypes.optimize files in
  let _, files = Krml.DataTypes.everything files in
  let files = Krml.Simplify.optimize_lets files in
  let files = Krml.Simplify.sequence_to_let#visit_files () files in
  let files = Krml.Simplify.hoist#visit_files [] files in
  let files = Krml.Simplify.misc_cosmetic#visit_files () files in
  let files = Krml.Simplify.let_to_sequence#visit_files () files in
  let files = Krml.Inlining.cross_call_analysis files in

  Eurydice.Logging.log "Phase3" "%a" pfiles files;
  let errors, files = Krml.Checker.check_everything ~warn:true files in
  if errors then
    exit 1;

  let macros =
    (object(self)
      inherit [_] Krml.Ast.reduce
      method private zero = Krml.Idents.LidSet.empty
      method private plus = Krml.Idents.LidSet.union
      method! visit_DExternal _ _ _ n name _ _ =
        if n > 0 then
          Krml.Idents.LidSet.singleton name
        else
          self#zero
    end)#visit_files () files
  in
  let macros = Krml.Idents.LidSet.union macros Eurydice.Builtin.macros in
  let open Krml in
  let file_of_map = Bundle.mk_file_of files in
  let c_name_map = Simplify.allocate_c_names files in
  let deps = Bundles.direct_dependencies_with_internal files file_of_map in
  let files = AstToCStar.mk_files files c_name_map Idents.LidSet.empty macros in

  let headers = CStarToC11.mk_headers c_name_map files in
  let deps = CStarToC11.drop_empty_headers deps headers in
  let internal_headers = Bundles.StringSet.of_list
    (List.filter_map (function (name, C11.Internal _) -> Some name | _ -> None) headers)
  in
  let public_headers = Bundles.StringSet.of_list
    (List.filter_map (function (name, C11.Public _) -> Some name | _ -> None) headers)
  in
  let files = CStarToC11.mk_files c_name_map files in
  ignore (Output.write_c files internal_headers deps);
  ignore (Output.write_h headers public_headers deps);

  Printf.printf "✅ Done\n"
