defmodule FDB.Coder.Dynamic do
  @behaviour FDB.Coder.Behaviour

  def new do
    coders = %{
      byte_string: FDB.Coder.ByteString.new(),
      unicode_string: FDB.Coder.UnicodeString.new(),
      integer: FDB.Coder.Integer.new(),
      boolean: FDB.Coder.Boolean.new(),
      arbitrary_integer: FDB.Coder.ArbitraryInteger.new(),
      uuid: FDB.Coder.UUID.new()
    }

    %FDB.Coder{module: __MODULE__, opts: coders}
  end

  @impl true
  def encode(_, _) do
    raise "encode not supported"
  end

  @impl true
  def decode(rest, coders) do
    {loop(rest, coders, {}), <<>>}
  end

  @impl true
  def range(_, _) do
    raise "range not supported"
  end

  defp loop(<<>>, coders, acc), do: acc

  defp loop(rest, coders, acc) do
    {acc, rest} = do_decode(rest, coders, acc)
    loop(rest, coders, acc)
  end

  defp do_decode(<<0x00>> <> rest = full, coders, acc),
    do: {Tuple.append(acc, nil), rest}

  defp do_decode(<<0x01>> <> rest = full, coders, acc),
    do: apply_coder(coders.byte_string, full, coders, acc)

  defp do_decode(<<0x02>> <> rest = full, coders, acc),
    do: apply_coder(coders.unicode_string, full, coders, acc)

  defp do_decode(<<0x20>> <> <<n::binary-size(4), rest::binary>>, coders, acc),
    do: {Tuple.append(acc, n), rest}

  defp do_decode(<<0x21>> <> <<n::binary-size(8), rest::binary>>, coders, acc),
    do: {Tuple.append(acc, n), rest}

  defp do_decode(<<0x30>> <> rest = full, coders, acc),
    do: apply_coder(coders.uuid, full, coders, acc)

  defp do_decode(<<0x05>> <> rest = full, coders, acc) do
    {value, rest} = do_decode_nested_tuple(rest, coders, {})
    {Tuple.append(acc, value), rest}
  end

  defp do_decode(<<x::integer-size(8), rest::binary>> = full, coders, acc) when x in 0x0C..0x1C,
    do: apply_coder(coders.integer, full, coders, acc)

  defp do_decode(<<x::integer-size(8), rest::binary>> = full, coders, acc)
       when x in [0x26, 0x27],
       do: apply_coder(coders.boolean, full, coders, acc)

  defp do_decode(<<x::integer-size(8), rest::binary>> = full, coders, acc)
       when x in [0x1D, 0x0B],
       do: apply_coder(coders.arbitrary_integer, full, coders, acc)

  defp apply_coder(c, rest, coders, acc) do
    {value, rest} = c.module.decode(rest, c.opts)
    {Tuple.append(acc, value), rest}
  end

  defp do_decode_nested_tuple(<<0x00, 0xFF>> <> _rest = full, coders, values) do
    {values, <<0xFF>> <> rest} = do_decode(full, coders, values)
    do_decode_nested_tuple(rest, coders, values)
  end

  defp do_decode_nested_tuple(<<0x00>> <> rest, coders, values), do: {values, rest}

  defp do_decode_nested_tuple(rest, coders, values) do
    {values, rest} = do_decode(rest, coders, values)
    do_decode_nested_tuple(rest, coders, values)
  end
end
