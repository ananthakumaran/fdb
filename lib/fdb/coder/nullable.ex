defmodule FDB.Coder.Nullable do
  @behaviour FDB.Coder.Behaviour

  def new(coder) do
    %FDB.Coder{module: __MODULE__, opts: coder}
  end

  @code <<0x00>>

  @impl true
  def encode(nil, _coder), do: @code
  def encode(value, coder), do: coder.module.encode(value, coder.opts)

  @impl true
  def decode(@code <> rest, _), do: {nil, rest}
  def decode(value, coder), do: coder.module.decode(value, coder.opts)

  @impl true
  def range(nil, _), do: {<<0x00>>, <<0xFF>>}

  def range(value, coder) do
    encoded = encode(value, coder)
    {encoded <> <<0x00>>, encoded <> <<0xFF>>}
  end
end
