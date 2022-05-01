defmodule CredoFixer.CondStatementsFixer do
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
        {:cond, cond_meta, [[{{:__block__, _, [:do]}, [{:->, _, [[first_cond], first_cond_do]}, {:->, _, [_, second_cond_do]} = second_clause]}]]} = initial ->
          if is_always_matching_condition?(second_clause) do
            {:if, cond_meta, [first_cond, [{{:__block__, [], [:do]},  first_cond_do}, {{:__block__, [], [:else]}, second_cond_do}]]}
          else
            initial
          end

        other -> other
      end
    )
  end

  defp is_always_matching_condition?(clause) do
    case clause do
      {:->, _meta, [[{name, _meta2, nil}], _args]} when is_atom(name) ->
        name |> to_string |> String.starts_with?("_")

      {:->, _meta, [[{:__block__, _, [true]}], _args]} ->
        true

      _ ->
        false
    end
  end
end