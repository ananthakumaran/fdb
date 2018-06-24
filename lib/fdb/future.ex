defmodule FDB.Future do
  alias FDB.Native
  alias FDB.Utils
  alias FDB.Future

  defstruct resource: nil

  def create(resource) do
    %Future{resource: resource}
  end

  def await(%Future{resource: resource}) when is_function(resource) do
    resource.()
  end

  def await(%Future{resource: resource}) do
    ref = make_ref()

    Native.future_resolve(resource, ref)
    |> Utils.verify_result()

    receive do
      {0, ^ref, value} ->
        value

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    end
  end

  def map(%Future{} = future, cb) do
    create(fn ->
      cb.(await(future))
    end)
  end
end
