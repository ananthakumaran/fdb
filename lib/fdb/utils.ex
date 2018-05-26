defmodule FDB.Utils do
  def verify_result(0), do: :ok
  def verify_result({0, result}), do: result
  def verify_result(code) when is_integer(code), do: raise(FDB.Error, Native.get_error(code))

  def verify_result({code, _}) when is_integer(code),
    do: raise(FDB.Error, Native.get_error(code))
end