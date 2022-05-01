# Töös kirjeldada mida fixer endast kujutab, mis on ta ülesanne.
defmodule CredoFixer.ParenthesesOnZeroArityDefsFixer do
  alias Credo.Check.Params

  def run_on_all_source_files(source_files, ast_by_source_file, params) do
    Enum.reduce(
      source_files,
      ast_by_source_file,
      fn source_file, acc ->
        new_ast = run_on_file(Map.fetch!(acc, source_file), params)

        Map.put(acc, source_file, new_ast)
      end
    )
  end

  @def_ops ~w(def defp defmacro defmacrop)a

  # def(a(param1, param2), do: 1)
  defp run_on_file(ast, params) do
    parens? = Params.get(params, :parens, Credo.Check.Readability.ParenthesesOnZeroArityDefs)

    Macro.prewalk(ast, fn
      {def_op, def_meta, [{fun_name, fun_meta, nil} | other]}
      when def_op in @def_ops and is_atom(fun_name) and parens? ->
        {def_op, def_meta, [{fun_name, fun_meta, []} | other]}

      {def_op, def_meta, [{fun_name, fun_meta, []} | other]}
      when def_op in @def_ops and is_atom(fun_name) and not parens? ->
        {def_op, def_meta, [{fun_name, fun_meta, nil} | other]}

      other ->
        other
    end)
  end
end
