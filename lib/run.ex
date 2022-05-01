defmodule CredoFixer.Task.Run do
  use Credo.Execution.Task

  alias CredoFixer.Runner

  def call(exec, _opts \\ []) do
    source_files = get_source_files(exec)

    :ok = Runner.run(source_files, exec)

    exec
  end
end
