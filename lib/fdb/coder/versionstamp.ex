defmodule FDB.Coder.Versionstamp do
  alias FDB.Versionstamp
  use FDB.Coder.Behaviour

  @spec new() :: FDB.Coder.t()
  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @code <<0x33>>

  @impl true
  def encode(%Versionstamp{raw: raw}, _), do: @code <> raw
  @impl true
  def decode(<<@code, raw::binary-size(12), rest::binary>>, _), do: {Versionstamp.new(raw), rest}
end
