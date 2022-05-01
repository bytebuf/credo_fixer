defmodule CredoFixer.Plugin do
  import Credo.Plugin

  def init(exec) do
    register_command(exec, "fix", CredoFixer.FixCommand)
  end
end
