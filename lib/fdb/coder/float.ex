defmodule FDB.Coder.Float do
  @moduledoc """
  Note that implementation of Float is not fully compatible with the
  [spec](https://github.com/apple/foundationdb/blob/master/design/tuple.md#ieee-binary-floating-point). It
  uses the erlang floating point implementation which is not fully
  compatible with the IEEE Binary Floating Point spec. It doesn't
  supports values like NaN, Infinity etc. As long as these values are
  not used by other language bindings this coder would work
  """
  use FDB.Coder.Behaviour
  use Bitwise

  @spec new(32 | 64) :: FDB.Coder.t()
  def new(bits \\ 32) when bits == 32 or bits == 64 do
    %FDB.Coder{module: __MODULE__, opts: bits}
  end

  @code32 <<0x20>>
  @code64 <<0x21>>

  @impl true
  def encode(n, 32), do: @code32 <> do_encode(<<n::32-float-big>>)
  def encode(n, 64), do: @code64 <> do_encode(<<n::64-float-big>>)

  @impl true
  def decode(@code32 <> <<n::binary-size(4), rest::binary>>, 32) do
    <<n::32-float-big>> = do_decode(n)
    {n, rest}
  end

  def decode(@code64 <> <<n::binary-size(8), rest::binary>>, 64) do
    <<n::64-float-big>> = do_decode(n)
    {n, rest}
  end

  defp do_encode(<<sign::big-integer-size(8), rest::binary>> = full) do
    if (sign &&& 0x80) != 0x00 do
      :binary.bin_to_list(full)
      |> Enum.map(fn e -> 0xFF ^^^ e end)
      |> IO.iodata_to_binary()
    else
      <<0x80 ^^^ sign>> <> rest
    end
  end

  defp do_decode(<<sign::big-integer-size(8), rest::binary>> = full) do
    if (sign &&& 0x80) == 0x00 do
      :binary.bin_to_list(full)
      |> Enum.map(fn e -> 0xFF ^^^ e end)
      |> IO.iodata_to_binary()
    else
      <<0x80 ^^^ sign>> <> rest
    end
  end
end
