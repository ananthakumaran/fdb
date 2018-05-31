defmodule FDB.Coder.Boolean do
  @behaviour FDB.Coder.Behaviour

  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @t <<0x26>>
  @f <<0x27>>

  @impl true
  def encode(true, _), do: @t
  def encode(false, _), do: @f

  @impl true
  def decode(@t <> rest, _), do: {true, rest}
  def decode(@f <> rest, _), do: {false, rest}

  @impl true
  def range(nil, _), do: {<<0x00>>, <<0xFF>>}

  def range(value, opts) do
    encoded = encode(value, opts)
    {encoded <> <<0x00>>, encoded <> <<0xFF>>}
  end
end
