defmodule FDB.Coder.Float do
  @moduledoc """
  Values that can't be represented by erlang float will be returned as
  a two element tuple. {:inf | :"-inf" | :NaN, binary}
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
  def encode(n, 32), do: @code32 <> do_encode(encode_float_32(n))
  def encode(n, 64), do: @code64 <> do_encode(encode_float_64(n))

  @impl true
  def decode(@code32 <> <<n::binary-size(4), rest::binary>>, 32) do
    {decode_float_32(do_decode(n)), rest}
  end

  def decode(@code64 <> <<n::binary-size(8), rest::binary>>, 64) do
    {decode_float_64(do_decode(n)), rest}
  end

  defp do_encode(<<sign::big-integer-size(8), rest::binary>> = full) do
    if (sign &&& 0x80) != 0x00 do
      :binary.bin_to_list(full)
      |> Enum.map(fn e -> Bitwise.bxor(0xFF, e) end)
      |> IO.iodata_to_binary()
    else
      <<Bitwise.bxor(0x80, sign)>> <> rest
    end
  end

  defp do_decode(<<sign::big-integer-size(8), rest::binary>> = full) do
    if (sign &&& 0x80) == 0x00 do
      :binary.bin_to_list(full)
      |> Enum.map(fn e -> Bitwise.bxor(0xFF, e) end)
      |> IO.iodata_to_binary()
    else
      <<Bitwise.bxor(0x80, sign)>> <> rest
    end
  end

  def encode_float_64({:inf, f}), do: f
  def encode_float_64({:"-inf", f}), do: f
  def encode_float_64({:NaN, f}), do: f
  def encode_float_64(n) when is_number(n), do: <<n::64-float-big>>

  def decode_float_64(f = <<0::1, 2047::11, 0::52>>), do: {:inf, f}
  def decode_float_64(f = <<1::1, 2047::11, 0::52>>), do: {:"-inf", f}
  def decode_float_64(f = <<_::1, 2047::11, _::52>>), do: {:NaN, f}
  def decode_float_64(<<n::64-float-big>>), do: n

  def encode_float_32({:NaN, f}), do: f
  def encode_float_32({:inf, f}), do: f
  def encode_float_32({:"-inf", f}), do: f
  def encode_float_32(n) when is_number(n), do: <<n::32-float-big>>

  def decode_float_32(f = <<0::1, 255::8, 0::23>>), do: {:inf, f}
  def decode_float_32(f = <<1::1, 255::8, 0::23>>), do: {:"-inf", f}
  def decode_float_32(f = <<_::1, 255::8, _::23>>), do: {:NaN, f}
  def decode_float_32(<<n::32-float-big>>), do: n
end
