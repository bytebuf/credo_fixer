defmodule CredoFixer.AliasOrderFixer do
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
    Macro.prewalk(ast, fn
      {:defmodule, def_mod_meta,
       [
         {:__aliases__, _, module_name_list} = def_mod_name,
         [{{:__block__, do_literal_meta, [:do]}, {:__block__, block_meta, module_nodes}}]
       ]} ->
        multi_alias_sorted_nodes =
          Enum.map(
            module_nodes,
            fn
              {:alias, alias_meta, [{{:., _, [_, :{}]} = dot, dot_meta, multi_aliases}]} ->
                sorted_multi_aliases =
                  Enum.sort(
                    multi_aliases,
                    fn {:__aliases__, _, first}, {:__aliases__, _, second} ->
                      compare_name_from_atom_list(first) < compare_name_from_atom_list(second)
                    end
                  )

                {:alias, alias_meta, [{dot, dot_meta, sorted_multi_aliases}]}

              node ->
                node
            end
          )

        {enhanced_nodes, _} =
          Enum.map_reduce(
            multi_alias_sorted_nodes,
            {0, nil},
            fn {op, node_meta, _} = module_node, {counter, prev} ->
              node_with_order_num =
                Macro.update_meta(module_node, &Keyword.put(&1, :order, counter))

              node_with_alias_group_id =
                case {op, prev} do
                  {:alias, {:alias, prev_meta, _}} ->
                    curr_line = Keyword.fetch!(node_meta, :line)
                    prev_line = Keyword.fetch!(prev_meta, :line)

                    alias_group_id =
                      if curr_line - 1 == prev_line do
                        Keyword.fetch!(prev_meta, :alias_group_id)
                      else
                        counter
                      end

                    Macro.update_meta(
                      node_with_order_num,
                      &Keyword.put(&1, :alias_group_id, alias_group_id)
                    )

                  {:alias, _} ->
                    Macro.update_meta(
                      node_with_order_num,
                      &Keyword.put(&1, :alias_group_id, counter)
                    )

                  _other ->
                    node_with_order_num
                end

              acc = {counter + 1, node_with_alias_group_id}
              {node_with_alias_group_id, acc}
            end
          )

        {not_reorderable_groups, _} =
          Enum.reduce(
            enhanced_nodes,
            {MapSet.new(), %{}},
            fn module_node, {not_reorderable_groups, available_aliases} ->
              case module_node do
                {:alias, meta, _} ->
                  new_available_alias_prefixes = alias_as(module_node, module_name_list)
                  referenced_alias = extract_aliasable_module(module_node)

                  alias_group_id = Keyword.fetch!(meta, :alias_group_id)

                  new_not_reorderable_groups =
                    if referenced_alias != :__MODULE__ &&
                         MapSet.member?(
                           Map.get(available_aliases, alias_group_id, MapSet.new()),
                           referenced_alias
                         ) do
                      MapSet.put(not_reorderable_groups, alias_group_id)
                    else
                      not_reorderable_groups
                    end

                  new_available_aliases =
                    Enum.reduce(
                      new_available_alias_prefixes,
                      available_aliases,
                      fn new_available_alias, acc ->
                        Map.put(
                          acc,
                          alias_group_id,
                          MapSet.put(
                            Map.get(acc, alias_group_id, MapSet.new()),
                            new_available_alias
                          )
                        )
                      end
                    )

                  {new_not_reorderable_groups, new_available_aliases}

                _other ->
                  {not_reorderable_groups, available_aliases}
              end
            end
          )

        sorted_nodes =
          Enum.sort(
            enhanced_nodes,
            fn
              {:alias, first_meta, _} = first, {:alias, second_meta, _} = second ->
                first_order = Keyword.fetch!(first_meta, :order)
                second_order = Keyword.fetch!(second_meta, :order)
                first_group_id = Keyword.fetch!(first_meta, :alias_group_id)
                second_group_id = Keyword.fetch!(second_meta, :alias_group_id)

                if first_group_id == second_group_id &&
                     !MapSet.member?(not_reorderable_groups, first_group_id) do
                  compare_name(first) < compare_name(second)
                else
                  first_order < second_order
                end

              {_, first_meta, _}, {_, second_meta, _} ->
                first_order = Keyword.fetch!(first_meta, :order)
                second_order = Keyword.fetch!(second_meta, :order)

                first_order < second_order
            end
          )

        fixed_newlines_nodes =
          sorted_nodes
          |> Enum.reverse()
          |> Enum.map_reduce(nil, fn
            {:alias, curr_meta, _} = curr, {:alias, next_meta, _} ->
              new_curr_node =
                if Keyword.fetch!(curr_meta, :alias_group_id) ==
                     Keyword.fetch!(next_meta, :alias_group_id) do
                  Macro.update_meta(
                    curr,
                    &Keyword.put(
                      &1,
                      :end_of_expression,
                      &1 |> Keyword.get(:end_of_expression, []) |> Keyword.delete(:newlines)
                    )
                  )
                else
                  Macro.update_meta(
                    curr,
                    &Keyword.put(
                      &1,
                      :end_of_expression,
                      &1 |> Keyword.get(:end_of_expression, []) |> Keyword.put(:newlines, 2)
                    )
                  )
                end

              {new_curr_node, new_curr_node}

            {:alias, _, _} = curr, next when not is_nil(next) ->
              new_curr_node =
                Macro.update_meta(
                  curr,
                  &Keyword.put(
                    &1,
                    :end_of_expression,
                    &1 |> Keyword.get(:end_of_expression, []) |> Keyword.put(:newlines, 2)
                  )
                )

              {new_curr_node, new_curr_node}

            curr, _ ->
              {curr, curr}
          end)
          |> elem(0)
          |> Enum.reverse()

        {:defmodule, def_mod_meta,
         [
           def_mod_name,
           [
             {{:__block__, do_literal_meta, [:do]},
              {:__block__, block_meta, fixed_newlines_nodes}}
           ]
         ]}

      other ->
        other
    end)
  end

  defp compare_name(
         {:alias, _meta,
          [
            {{:., _, [{:__aliases__, _, prefix_list}, :{}]}, _,
             [{:__aliases__, _, first_multi_alias} | _]}
          ]}
       ) do
    compare_name_from_atom_list(prefix_list ++ first_multi_alias)
  end

  defp compare_name(
         {:alias, _meta,
          [{{:., _, [{:__MODULE__, _, _}, :{}]}, _, [{:__aliases__, _, first_multi_alias} | _]}]}
       ) do
    compare_name_from_atom_list([:__MODULE__] ++ first_multi_alias)
  end

  defp compare_name({:alias, _meta, [{:__aliases__, _, name_list} | _]}) do
    compare_name_from_atom_list(name_list)
  end

  defp compare_name({:alias, _meta, [{:__MODULE__, _, _} | _]}), do: "__module__"

  defp compare_name_from_atom_list(name_list) do
    Enum.map_join(name_list, ".", fn
      {:__MODULE__, _, _} ->
        "__module__"

      name_part when is_atom(name_part) ->
        name_part |> Atom.to_string() |> String.downcase()
    end)
  end

  defp extract_aliasable_module({:alias, _, [{:__MODULE__, _, _} | _]}), do: :__MODULE__

  defp extract_aliasable_module({:alias, _, [{{:., _, [{:__MODULE__, _, _}, :{}]}, _, _} | _]}),
    do: :__MODULE__

  defp extract_aliasable_module(
         {:alias, _, [{{:., _, [{:__aliases__, _, [aliasable | _]}, :{}]}, _, _} | _]}
       )
       when is_atom(aliasable),
       do: aliasable

  defp extract_aliasable_module({:alias, _, [{:__aliases__, _, [{:__MODULE__, _, _} | _]} | _]}),
    do: :__MODULE__

  defp extract_aliasable_module({:alias, _, [{:__aliases__, _, [aliasable | _]} | _]})
       when is_atom(aliasable),
       do: aliasable

  defp alias_as({:alias, _meta, [_aliasable | [second_arg]]}, _) do
    [
      {
        {:__block__, _, [:as]},
        {:__aliases__, _, [aliased_as]}
      }
    ] = second_arg

    [aliased_as]
  end

  defp alias_as({:alias, _, [{:__aliases__, _, name_list}]}, _) when is_list(name_list) do
    [List.last(name_list)]
  end

  defp alias_as({:alias, _, [{:__MODULE__, _, _}]}, module_name_list),
    do: [List.last(module_name_list)]

  defp alias_as({:alias, _, [{{:., _, [_, :{}]}, _, multi_aliases}]}, _) do
    Enum.map(
      multi_aliases,
      fn {:__aliases__, _, name_list} when is_list(name_list) -> List.last(name_list) end
    )
  end
end
