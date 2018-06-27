defmodule FDB.Coder.ArbitraryInteger do
  use FDB.Coder.Behaviour
  use Bitwise

  @spec new() :: FDB.Coder.t()
  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @positive <<0x1D>>
  @negative <<0x0B>>

  @impl true
  def encode(n, _) when n < 0 do
    binary = unsigned_to_bin(-n)
    @negative <> complement(<<byte_size(binary)::integer>> <> binary)
  end

  def encode(n, _) when n >= 0 do
    binary = unsigned_to_bin(n)
    @positive <> <<byte_size(binary)::integer>> <> binary
  end

  def encode(n, _) when n == 0, do: <<0x14>>

  @impl true
  def decode(@negative <> rest, _) do
    <<size::binary-size(1), rest::binary>> = rest
    <<size::integer-size(8)>> = complement(size)
    <<n::binary-size(size), rest::binary>> = rest
    <<n::integer-big-unit(8)-size(size)>> = complement(n)
    {-n, rest}
  end

  def decode(@positive <> rest, _) do
    <<size::integer-size(8), rest::binary>> = rest
    <<n::integer-big-unit(8)-size(size), rest::binary>> = rest
    {n, rest}
  end

  defp unsigned_to_bin(i) when is_integer(i) and i >= 0, do: unsigned_to_bin(i, [])
  defp unsigned_to_bin(0, acc), do: IO.iodata_to_binary(acc)
  defp unsigned_to_bin(n, acc), do: unsigned_to_bin(bsr(n, 8), [band(n, 0xFF) | acc])

  defp complement(<<>>), do: <<>>

  defp complement(<<n::integer-size(8), rest::binary>>) do
    <<(~~~n)::integer-8, complement(rest)::binary>>
  end
end
