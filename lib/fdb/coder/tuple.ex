defmodule FDB.Coder.Tuple do
  @moduledoc """
  This should be only used at the top level. For nested tuple
  `FDB.Coder.NestedTuple` should be used
  """
  use FDB.Coder.Behaviour

  @spec new(tuple) :: FDB.Coder.t()
  def new(coders) do
    %FDB.Coder{module: __MODULE__, opts: Tuple.to_list(coders)}
  end

  @impl true
  def encode(values, coders) do
    values = Tuple.to_list(values)
    validate_length!(values, coders)

    do_encode(coders, values)
  end

  @impl true
  def decode(rest, coders) do
    Enum.reduce(coders, {{}, rest}, fn coder, {values, rest} ->
      {elem, rest} = coder.module.decode(rest, coder.opts)
      {Tuple.append(values, elem), rest}
    end)
  end

  @impl true
  def range(nil, _), do: {<<>>, :partial}

  def range(values, coders) do
    values = Tuple.to_list(values)
    {encoded, s} = do_range(Enum.take(coders, length(values)), values)

    if length(values) == length(coders) do
      {encoded, s}
    else
      {encoded, :partial}
    end
  end

  defp do_range(coders, values) do
    Enum.zip(coders, values)
    |> Enum.reduce({<<>>, :partial}, fn {coder, value}, {encoded, _state} ->
      {e, s} = coder.module.range(value, coder.opts)
      {encoded <> e, s}
    end)
  end

  defp do_encode(coders, values) do
    Enum.zip(coders, values)
    |> Enum.map(fn {coder, value} ->
      coder.module.encode(value, coder.opts)
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
