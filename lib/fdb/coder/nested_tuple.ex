defmodule FDB.Coder.NestedTuple do
  @behaviour FDB.Coder.Behaviour

  def new(coders) do
    %FDB.Coder{module: __MODULE__, opts: Tuple.to_list(coders)}
  end

  @code <<0x05>>
  @end_code <<0x00>>
  @null <<0x00, 0xFF>>
  @null_suffix <<0xFF>>

  @impl true
  def encode(values, coders) do
    values = Tuple.to_list(values)
    validate_length!(values, coders)

    @code <> do_encode(coders, values) <> @end_code
  end

  @impl true
  def decode(@code <> rest, coders) do
    {value, @end_code <> rest} =
      Enum.reduce(coders, {{}, rest}, fn
        coder, {values, @null <> _rest = full} ->
          {nil, @null_suffix <> rest} = coder.module.decode(full, coder.opts)
          {Tuple.append(values, nil), rest}

        coder, {values, rest} ->
          {elem, rest} = coder.module.decode(rest, coder.opts)
          {Tuple.append(values, elem), rest}
      end)

    {value, rest}
  end

  @impl true
  def range(nil, _), do: {<<0x00>>, <<0xFF>>}
  def range(values, coders) do
    values = Tuple.to_list(values)
    if Enum.empty?(values) do
      {<<0x00>>, <<0xFF>>}
    else
      encoded = @code <> do_encode(values, Enum.take(coders, length(values)))
      encoded = if length(values) == length(coders) do
        encoded <> @end_code
      else
        encoded
      end
      {encoded <> <<0x00>>, encoded <> <<0xFF>>}
    end
  end

  defp do_encode(coders, values) do
    Enum.zip(coders, values)
    |> Enum.map(fn {coder, value} ->
      coder.module.encode(value, coder.opts) <>
      if is_nil(value) do
        @null_suffix
      else
        <<>>
      end
    end)
    |> Enum.join(<<>>)
  end

  defp validate_length!(values, coders) do
    actual = length(values)
    expected = length(coders)

    if actual != expected do
      raise ArgumentError,
            "Invalid value: expected tuple with length #{expected}, got #{List.to_tuple(values)}"
    end
  end
end
