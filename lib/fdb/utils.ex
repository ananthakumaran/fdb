defmodule FDB.Utils do
  @moduledoc false

  alias FDB.Native

  @spec verify_result({integer, result}) :: result when result: var
  def verify_result({0, result}), do: result

  def verify_result({code, _}) when is_integer(code),
    do: raise(FDB.Error, code: code, message: Native.get_error(code))

  @spec verify_ok(integer) :: :ok
  def verify_ok(0), do: :ok

  def verify_ok(code) when is_integer(code),
    do: raise(FDB.Error, code: code, message: Native.get_error(code))

  def binary_cut(binary, at) do
    first = binary_part(binary, 0, at)
    rest = binary_part(binary, at, byte_size(binary) - at)
    {first, rest}
  end

  def normalize_bool(0), do: 0
  def normalize_bool(1), do: 1
  def normalize_bool(false), do: 0
  def normalize_bool(true), do: 1

  def normalize_bool(other),
    do: raise(ArgumentError, "Expected boolean value, got: #{inspect(other)}")

  def normalize_bool_values(map, _) when map == %{}, do: %{}

  def normalize_bool_values(map, keys) do
    Enum.reduce(keys, map, fn key, map ->
      if Map.has_key?(map, key) do
        Map.put(map, key, normalize_bool(Map.get(map, key)))
      else
        map
      end
    end)
  end

  def verify_value(map, key, validator) do
    if Map.has_key?(map, key) do
      value = Map.get(map, key)

      cond do
        validator == :positive_integer && (!is_integer(value) || value < 0) ->
          raise ArgumentError,
                "Invalid option value for key #{key}: Expected positive integer, got: #{
                  inspect(value)
                }"

        is_function(validator) ->
          validator.(value)

        true ->
          :ok
      end
    end

    map
  end

  def strinc(text) do
    text = String.replace(text, ~r/#{<<0xFF>>}*\z/, "")

    case text do
      "" ->
        <<0x00>>

      _ ->
        {prefix, <<last::integer>>} = binary_cut(text, byte_size(text) - 1)
        prefix <> <<last + 1::integer>>
    end
  end

  def starts_with?(binary, prefix) do
    :binary.longest_common_prefix([binary, prefix]) == byte_size(prefix)
  end
end
