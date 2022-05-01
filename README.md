# CredoFixer

This implements autocorrect for Credo.

## Installation

1. Add the library to your dependencies.

```elixir
def deps do
  [
    {:credo_fixer, git: "https://github.com/bytebuf/credo_fixer"}
  ]
end
```

2. Add the plugin to your `.credo.exs` file:
```elixir
%{
  #
  configs: [
    %{
      plugins: [
        {CredoFixer.Plugin, []}
      ]
    }
  ]
}
```

3. Run `mix credo fix`
