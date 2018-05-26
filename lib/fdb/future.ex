defmodule FDB.Future do
  alias FDB.Native
  alias FDB.Utils

  def resolve(future) do
    ref = make_ref()

    Native.future_resolve(future, ref)
    |> Utils.verify_result()

    receive do
      {0, ^ref, value} -> value
      {error_code, ^ref, nil} -> raise FDB.Error, Native.get_error(error_code)
    end
  end
end
