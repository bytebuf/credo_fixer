defmodule CredoFixer.FixCommand do
  @moduledoc false

  use Credo.CLI.Command

  alias Credo.CLI.Output.UI
  alias Credo.Execution

  def init(exec) do
    Execution.put_pipeline(exec, __MODULE__,
      load_and_validate_source_files: [Credo.CLI.Task.LoadAndValidateSourceFiles],
      prepare_analysis: [Credo.CLI.Task.PrepareChecksToRun],
      run_analysis: [CredoFixer.Task.Run]
    )
  end

  def call(exec, _) do
    UI.puts("Running autocorect")

    Execution.run_pipeline(exec, __MODULE__)
  end
end
