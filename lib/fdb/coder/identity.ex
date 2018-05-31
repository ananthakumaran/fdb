defmodule FDB.Coder.Identity do
  @behaviour FDB.Coder.Behaviour

  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @impl true
  def encode(value, _), do: value
  @impl true
  def decode(value, _), do: {value, <<>>}
  @impl true
  def range(nil, _), do: {<<0x00>>, <<0xFF>>}
  def range(value, _), do: {value, value}
end
