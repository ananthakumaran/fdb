defmodule FDB.OptionBuilder do
  @moduledoc false

  @app Mix.Project.config()[:app]
  @path :filename.join(:code.priv_dir(@app), 'fdb.options')
  @external_resource @path

  def scopes() do
    import SweetXml

    File.read!(@path)
    |> xpath(
      ~x"//Options/Scope"l,
      name: ~x"@name"s,
      options: [
        ~x"./Option"l,
        name: ~x"@name"s,
        code: ~x"@code"i,
        param_type: ~x"@paramType"s,
        param_description: ~x"@paramDescription"s,
        description: ~x"@description"s
      ]
    )
  end

  def option_methods(scope) do
    Enum.map(scope.options, fn option ->
      type =
        if String.length(option.param_type) > 0 do
          "Type: `#{option.param_type}`"
        end

      doc =
        [
          option.param_description,
          type,
          option.description
        ]
        |> Enum.filter(&(&1 && String.length(&1) > 0))
        |> Enum.join("\n\n")

      name =
        String.downcase(Macro.underscore(scope.name) <> "_" <> option.name)
        |> String.to_atom()

      quote do
        @doc unquote(doc)
        def unquote(name)() do
          unquote(option.code)
        end
      end
    end)
  end

  defmacro defoptions do
    Enum.map(scopes(), &option_methods(&1))
  end
end
