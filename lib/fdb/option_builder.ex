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

  def validate_option(spec, option, value) do
    found = Map.has_key?(spec, option)

    if !found || !is_integer(option) do
      raise ArgumentError, "Invalid option: #{inspect(option)}"
    end

    value_type = Map.fetch!(spec, option)

    cond do
      value_type == nil && value != :none ->
        raise ArgumentError, "Invalid option value. This option doesn't accept any value"

      value_type == nil && value == :none ->
        true

      value_type != nil && value == :none ->
        raise ArgumentError,
              "Invalid option value. This option expects a value of type #{value_type}"

      (value_type == "String" && (!is_binary(value) || !String.valid?(value))) ||
        (value_type == "Bytes" && !is_binary(value)) ||
          (value_type == "Int" && !is_integer(value)) ->
        raise ArgumentError,
              "Invalid option value. This option expects a value of type #{value_type}, got: #{
                inspect(value)
              }"

      true ->
        true
    end
  end

  def validator_method(scope) do
    spec =
      Enum.map(scope.options, fn option ->
        type =
          if String.length(option.param_type) > 0 do
            option.param_type
          else
            nil
          end

        {option.code, type}
      end)
      |> Enum.into(%{})
      |> Macro.escape()

    name =
      String.downcase("verify_" <> Macro.underscore(scope.name))
      |> String.to_atom()

    quote do
      def unquote(name)(option) do
        FDB.OptionBuilder.validate_option(unquote(spec), option, :none)
      end

      def unquote(name)(option, value) do
        FDB.OptionBuilder.validate_option(unquote(spec), option, value)
      end
    end
  end

  defmacro defvalidators do
    Enum.map(scopes(), &validator_method(&1))
  end
end
