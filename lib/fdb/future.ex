defmodule FDB.Future do
  alias FDB.Native
  alias FDB.Utils

  def await(future) when is_function(future) do
    future.()
  end

  def await(future) when is_reference(future) do
    ref = make_ref()

    Native.future_resolve(future, ref)
    |> Utils.verify_result()

    receive do
      {0, ^ref, value} ->
        value

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    end
  end

  def map(future, cb) do
    fn ->
      cb.(await(future))
    end
  end
end
