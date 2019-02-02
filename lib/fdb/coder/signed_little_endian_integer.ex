defmodule FDB.Coder.SignedLittleEndianInteger do
  use FDB.Coder.Behaviour

  @spec new(pos_integer()) :: FDB.Coder.t()
  def new(bits \\ 128) do
    %FDB.Coder{module: __MODULE__, opts: bits}
  end

  @impl true
  def encode(n, bits) do
    <<n::little-integer-signed-size(bits)>>
  end

  @impl true
  def decode(value, bits) do
    <<n::little-integer-signed-size(bits), rest::binary>> = value
    {n, rest}
  end
end
