defmodule CredoFixer.UnlessWithElseFixer do
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
        {:unless, unless_meta, [condition, [{{:__block__, _, [:do]}, do_block}, {{:__block__, _, [:else]}, else_block}]]} ->
          {:if, unless_meta, [condition, [{{:__block__, [], [:do]}, else_block}, {{:__block__, [], [:else]}, do_block}]]}
        other -> other
      end
    )
  end
end