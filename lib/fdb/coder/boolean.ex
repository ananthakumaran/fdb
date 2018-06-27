defmodule FDB.Coder.Boolean do
  use FDB.Coder.Behaviour

  @spec new() :: FDB.Coder.t()
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
end
