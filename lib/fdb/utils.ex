defmodule FDB.Utils do
  alias FDB.Native

  def verify_result(0), do: :ok
  def verify_result({0, result}), do: result

  def verify_result(code) when is_integer(code),
    do: raise(FDB.Error, code: code, message: Native.get_error(code))

  def verify_result({code, _}) when is_integer(code),
    do: raise(FDB.Error, code: code, message: Native.get_error(code))

  def binary_cut(binary, at) do
    first = binary_part(binary, 0, at)
    rest = binary_part(binary, at, byte_size(binary) - at)
    {first, rest}
  end
end
