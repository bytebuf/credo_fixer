defmodule CredoFixer.SinglePipeFixer do
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
    enhanced_ast =
      Macro.prewalk(ast, fn
        {:|>, meta, children} when is_list(children) ->
          {:|>, meta, add_meta_to_children(children)}

        other ->
          other
      end)

    fixed_ast =
      Macro.prewalk(
        enhanced_ast,
        fn
          {:|>, meta, children} ->
            if Keyword.get(meta, :parent_is_pipe, false) || Enum.any?(children, &is_pipe(&1)) do
              {:|>, meta, children}
            else
              [first_argument, {callable, _callable_meta, existing_args}] = children

              existing_args_list =
                case existing_args do
                  nil -> []
                  args -> args
                end

              new_call_arguments = [first_argument | existing_args_list]

              {callable, meta, new_call_arguments}
            end

          other ->
            other
        end
      )

    Macro.prewalk(fixed_ast, fn
      {fun, meta, children} when is_list(meta) ->
        {fun, Keyword.delete(meta, :parent_is_pipe), children}

      other ->
        other
    end)
  end

  defp is_pipe({:|>, _, _}), do: true

  defp is_pipe(_), do: false

  defp add_meta_to_children(children) do
    Enum.map(
      children,
      fn child ->
        Macro.update_meta(child, fn meta -> meta ++ [parent_is_pipe: true] end)
      end
    )
  end
end
