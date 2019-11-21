defmodule FDB.Coder.Dynamic do
  use FDB.Coder.Behaviour

  @spec new() :: FDB.Coder.t()
  def new do
    coders = %{
      byte_string: FDB.Coder.ByteString.new(),
      unicode_string: FDB.Coder.UnicodeString.new(),
      integer: FDB.Coder.Integer.new(),
      boolean: FDB.Coder.Boolean.new(),
      arbitrary_integer: FDB.Coder.ArbitraryInteger.new(),
      uuid: FDB.Coder.UUID.new(),
      float32: FDB.Coder.Float.new(),
      float64: FDB.Coder.Float.new(64),
      versionstamp: FDB.Coder.Versionstamp.new()
    }

    %FDB.Coder{module: __MODULE__, opts: coders}
  end

  @impl true
  def encode({nil, nil}, _coders), do: <<0x00>>

  def encode({tag, value}, coders)
      when tag in [
             :byte_string,
             :unicode_string,
             :integer,
             :boolean,
             :arbitrary_integer,
             :uuid,
             :float32,
             :float64,
             :versionstamp
           ] do
    coder = coders[tag]
    coder.module.encode(value, coder.opts)
  end

  def encode({:nested, values}, coders) do
    encoded =
      Enum.map(Tuple.to_list(values), fn
        {nil, nil} -> <<0x00, 0xFF>>
        value -> encode(value, coders)
      end)
      |> Enum.join(<<>>)

    <<0x05>> <> encoded <> <<0x00>>
  end

  def encode(values, coders) when is_tuple(values) do
    Enum.map(Tuple.to_list(values), fn value ->
      encode(value, coders)
    end)
    |> Enum.join(<<>>)
  end

  @impl true
  def decode(rest, coders) do
    {loop(rest, coders, {}), <<>>}
  end

  defp loop(<<>>, _coders, acc), do: acc

  defp loop(rest, coders, acc) do
    {acc, rest} = do_decode(rest, coders, acc)
    loop(rest, coders, acc)
  end

  defp do_decode(<<0x00>> <> rest, _coders, acc),
    do: {Tuple.append(acc, {nil, nil}), rest}

  defp do_decode(<<0x01>> <> _rest = full, coders, acc),
    do: apply_coder(:byte_string, full, coders, acc)

  defp do_decode(<<0x02>> <> _rest = full, coders, acc),
    do: apply_coder(:unicode_string, full, coders, acc)

  defp do_decode(<<0x20>> <> _rest = full, coders, acc),
    do: apply_coder(:float32, full, coders, acc)

  defp do_decode(<<0x21>> <> _rest = full, coders, acc),
    do: apply_coder(:float64, full, coders, acc)

  defp do_decode(<<0x30>> <> _rest = full, coders, acc) do
    {value, rest} = coders[:uuid].module.decode(full, coders[:uuid].opts)
    {Tuple.append(acc, {:uuid, value <> rest}), ""}
  end

  defp do_decode(<<0x33>> <> _rest = full, coders, acc),
    do: apply_coder(:versionstamp, full, coders, acc)

  defp do_decode(<<0x05>> <> rest, coders, acc) do
    {value, rest} = do_decode_nested_tuple(rest, coders, {})
    {Tuple.append(acc, {:nested, value}), rest}
  end

  defp do_decode(<<x::integer-size(8), _rest::binary>> = full, coders, acc) when x in 0x0C..0x1C,
    do: apply_coder(:integer, full, coders, acc)

  defp do_decode(<<x::integer-size(8), _rest::binary>> = full, coders, acc)
       when x in [0x26, 0x27],
       do: apply_coder(:boolean, full, coders, acc)

  defp do_decode(<<x::integer-size(8), _rest::binary>> = full, coders, acc)
       when x in [0x1D, 0x0B],
       do: apply_coder(:arbitrary_integer, full, coders, acc)

  defp apply_coder(c, rest, coders, acc) do
    {value, rest} = coders[c].module.decode(rest, coders[c].opts)
    {Tuple.append(acc, {c, value}), rest}
  end

  defp do_decode_nested_tuple(<<0x00, 0xFF>> <> _rest = full, coders, values) do
    {values, <<0xFF>> <> rest} = do_decode(full, coders, values)
    do_decode_nested_tuple(rest, coders, values)
  end

  defp do_decode_nested_tuple(<<0x00>> <> rest, _coders, values), do: {values, rest}

  defp do_decode_nested_tuple(rest, coders, values) do
    {values, rest} = do_decode(rest, coders, values)
    do_decode_nested_tuple(rest, coders, values)
  end
end
