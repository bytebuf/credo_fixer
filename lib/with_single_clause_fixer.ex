defmodule CredoFixer.WithSingleClauseFixer do
  def run_on_all_source_files(source_files, ast_by_source_file, _params) do
    Enum.reduce(
      source_files,
      ast_by_source_file,
      fn source_file, acc ->
        new_ast = run_on_file(Map.fetch!(acc, source_file))

        Map.put(acc, source_file, new_ast)
      end
    )
  end

  defp run_on_file(ast) do
    Macro.prewalk(ast,
      fn
        {:with, _, [{:<-, _, [left, right]}, [{{:__block__, _, [:do]}, body}, {{:__block__, _, [:else]}, else_block}]]} ->
          first_case_clause = {:->, [], [[left], body]}

          {:case, [], [
            right,
            [do: [first_case_clause | else_block]]
          ]}
        other -> other
      end
    )
  end
end