defmodule FDB.Coder.Identity do
  use FDB.Coder.Behaviour

  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @impl true
  def encode(value, _), do: value
  @impl true
  def decode(value, _), do: {value, <<>>}
end
