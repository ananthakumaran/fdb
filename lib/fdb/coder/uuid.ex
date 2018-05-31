defmodule FDB.Coder.UUID do
  @behaviour FDB.Coder.Behaviour

  def new do
    %FDB.Coder{
      module: __MODULE__
    }
  end

  @code <<0x30>>

  @impl true
  def encode(value, _) do
    @code <> value
  end

  @impl true
  def decode(@code <> value, _) do
    <<uuid::binary-size(16), rest::binary>> = value
    {uuid, rest}
  end

  @impl true
  def range(nil, _), do: {<<0x00>>, <<0xFF>>}

  def range(value, opts) do
    encoded = encode(value, opts)
    {encoded <> <<0x00>>, encoded <> <<0xFF>>}
  end
end
