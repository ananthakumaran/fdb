defmodule FDB.Coder.Integer do
  use FDB.Coder.Behaviour
  use Bitwise

  def new do
    %FDB.Coder{module: __MODULE__}
  end

  @impl true
  def encode(n, _) when n in -0xFFFFFFFFFFFFFFFF..-0x0100000000000000,
    do: <<0x0C>> <> complement(<<-n::integer-big-64>>)

  def encode(n, _) when n in -0xFFFFFFFFFFFFFF..-0x01000000000000,
    do: <<0x0D>> <> complement(<<-n::integer-big-56>>)

  def encode(n, _) when n in -0xFFFFFFFFFFFF..-0x010000000000,
    do: <<0x0E>> <> complement(<<-n::integer-big-48>>)

  def encode(n, _) when n in -0xFFFFFFFFFF..-0x0100000000,
    do: <<0x0F>> <> complement(<<-n::integer-big-40>>)

  def encode(n, _) when n in -0xFFFFFFFF..-0x01000000,
    do: <<0x10>> <> complement(<<-n::integer-big-32>>)

  def encode(n, _) when n in -0xFFFFFF..-0x010000,
    do: <<0x11>> <> complement(<<-n::integer-big-24>>)

  def encode(n, _) when n in -0xFFFF..-0x0100,
    do: <<0x12>> <> complement(<<-n::integer-big-16>>)

  def encode(n, _) when n in -0xFF..-0x01, do: <<0x13>> <> complement(<<-n::integer-big-8>>)
  def encode(n, _) when n == 0, do: <<0x14>>
  def encode(n, _) when n in 0x01..0xFF, do: <<0x15>> <> <<n::integer-big-8>>
  def encode(n, _) when n in 0x0100..0xFFFF, do: <<0x16>> <> <<n::integer-big-16>>
  def encode(n, _) when n in 0x010000..0xFFFFFF, do: <<0x17>> <> <<n::integer-big-24>>
  def encode(n, _) when n in 0x01000000..0xFFFFFFFF, do: <<0x18>> <> <<n::integer-big-32>>
  def encode(n, _) when n in 0x0100000000..0xFFFFFFFFFF, do: <<0x19>> <> <<n::integer-big-40>>

  def encode(n, _) when n in 0x010000000000..0xFFFFFFFFFFFF,
    do: <<0x1A>> <> <<n::integer-big-48>>

  def encode(n, _) when n in 0x01000000000000..0xFFFFFFFFFFFFFF,
    do: <<0x1B>> <> <<n::integer-big-56>>

  def encode(n, _) when n in 0x0100000000000000..0xFFFFFFFFFFFFFFFF,
    do: <<0x1C>> <> <<n::integer-big-64>>

  @impl true
  def decode(<<0x0C>> <> rest, _) do
    <<n::binary-size(8), rest::binary>> = rest
    <<n::integer-big-64>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x0D>> <> rest, _) do
    <<n::binary-size(7), rest::binary>> = rest
    <<n::integer-big-56>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x0E>> <> rest, _) do
    <<n::binary-size(6), rest::binary>> = rest
    <<n::integer-big-48>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x0F>> <> rest, _) do
    <<n::binary-size(5), rest::binary>> = rest
    <<n::integer-big-40>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x10>> <> rest, _) do
    <<n::binary-size(4), rest::binary>> = rest
    <<n::integer-big-32>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x11>> <> rest, _) do
    <<n::binary-size(3), rest::binary>> = rest
    <<n::integer-big-24>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x12>> <> rest, _) do
    <<n::binary-size(2), rest::binary>> = rest
    <<n::integer-big-16>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x13>> <> rest, _) do
    <<n::binary-size(1), rest::binary>> = rest
    <<n::integer-big-8>> = complement(n)
    {-n, rest}
  end

  def decode(<<0x14>> <> rest, _), do: {0, rest}

  def decode(<<0x15>> <> rest, _) do
    <<n::integer-big-8, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x16>> <> rest, _) do
    <<n::integer-big-16, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x17>> <> rest, _) do
    <<n::integer-big-24, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x18>> <> rest, _) do
    <<n::integer-big-32, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x19>> <> rest, _) do
    <<n::integer-big-40, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x1A>> <> rest, _) do
    <<n::integer-big-48, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x1B>> <> rest, _) do
    <<n::integer-big-56, rest::binary>> = rest
    {n, rest}
  end

  def decode(<<0x1C>> <> rest, _) do
    <<n::integer-big-64, rest::binary>> = rest
    {n, rest}
  end

  defp complement(<<>>), do: <<>>

  defp complement(<<n::integer-size(8), rest::binary>>) do
    <<(~~~n)::integer-8, complement(rest)::binary>>
  end
end
