defmodule FDB.Coder.ByteString do
  use FDB.Coder.Behaviour

  @spec new() :: FDB.Coder.t()
  def new do
    %FDB.Coder{
      module: __MODULE__,
      opts: :binary.compile_pattern(<<0x00>>)
    }
  end

  @null <<0x00>>
  @escaped <<0x00, 0xFF>>
  @code <<0x01>>
  @suffix <<0x00>>

  @impl true
  def encode(value, null_pattern) do
    @code <> :binary.replace(value, null_pattern, @escaped, [:global]) <> @suffix
  end

  @impl true
  def decode(@code <> value, _), do: do_decode(value, <<>>)

  defp do_decode(@escaped <> rest, acc), do: do_decode(rest, <<acc::binary, @null>>)
  defp do_decode(@null, acc), do: {acc, <<>>}
  defp do_decode(@null <> rest, acc), do: {acc, rest}

  defp do_decode(<<char::binary-size(1)>> <> rest, acc),
    do: do_decode(rest, <<acc::binary, char::binary-size(1)>>)
end
