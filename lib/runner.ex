defmodule CredoFixer.Runner do
  alias Credo.Check.Params
  alias Credo.Execution
  alias Credo.SourceFile

  @fixer_modules %{
    Credo.Check.Readability.ParenthesesOnZeroArityDefs =>
      CredoFixer.ParenthesesOnZeroArityDefsFixer,
    Credo.Check.Readability.SinglePipe => CredoFixer.SinglePipeFixer,
    Credo.Check.Readability.AliasOrder => CredoFixer.AliasOrderFixer,
    Credo.Check.Readability.WithSingleClause => CredoFixer.WithSingleClauseFixer,
    Credo.Check.Refactor.NegatedConditionsInUnless => CredoFixer.NegatedConditionsInUnlessFixer,
    Credo.Check.Refactor.UnlessWithElse => CredoFixer.UnlessWithElseFixer,
    Credo.Check.Refactor.CondStatements => CredoFixer.CondStatementsFixer
  }

  def run(source_files, exec) when is_list(source_files) do
    check_tuples =
      exec
      |> Execution.checks()
      |> fix_deprecated_notation_for_checks_without_params()

    ast_by_source_file =
      Enum.reduce(
        source_files,
        %{},
        fn source_file, acc ->
          file_ast =
            source_file
            |> SourceFile.source()
            |> Sourceror.parse_string!()

          Map.put(acc, source_file, file_ast)
        end
      )

    updated_ast_by_source_file =
      Enum.reduce(
        check_tuples,
        ast_by_source_file,
        fn check_tuple, ast_by_source_file ->
          run_check(exec, check_tuple, ast_by_source_file)
        end
      )

    updated_ast_by_source_file
    |> Map.to_list()
    |> Enum.each(fn {source_file, new_ast} ->
      if new_ast != Map.fetch!(ast_by_source_file, source_file) do
        IO.puts("#{source_file.filename} has been modified")

        :ok = write_ast(source_file.filename, new_ast)
      end
    end)

    :ok
  end

  defp write_ast(filename, ast) do
    {_formatter_fun, formatter_opts} = Mix.Tasks.Format.formatter_for_file(filename)

    new_source = Sourceror.to_string(ast, formatter_opts) <> "\n"

    File.write!(filename, new_source)

    :ok
  end

  defp run_check(exec, {check, params}, ast_by_source_file)
       when is_map_key(@fixer_modules, check) do
    files_included = Params.files_included(params, check)
    files_excluded = Params.files_excluded(params, check)

    found_relevant_files =
      if files_included == [] and files_excluded == [] do
        []
      else
        exec
        |> Execution.working_dir()
        |> Credo.Sources.find_in_dir(files_included, files_excluded)
      end

    source_files =
      exec
      |> Execution.get_source_files()
      |> filter_source_files(found_relevant_files)

    fixer_module = Map.fetch!(@fixer_modules, check)
    fixer_module.run_on_all_source_files(source_files, ast_by_source_file, params)
  end

  defp run_check(_exec, {_check, _params}, ast_by_source_file), do: ast_by_source_file

  defp filter_source_files(source_files, []) do
    source_files
  end

  defp filter_source_files(source_files, files_included) do
    Enum.filter(source_files, fn source_file ->
      Enum.member?(files_included, Path.expand(source_file.filename))
    end)
  end

  defp fix_deprecated_notation_for_checks_without_params({checks, _, _}) do
    Enum.map(checks, fn
      {check} -> {check, []}
      {check, params} -> {check, params}
    end)
  end
end
